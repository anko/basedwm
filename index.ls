#!/usr/bin/env lsc
require! <[ x11 split async ewmh fs net ]>
{ words, keys } = require \prelude-ls
{ spawn, exec } = require \child_process

argv = require \yargs .argv

verbose-log = if argv.verbose then console.log else -> # no-op

exit = (error-code=0, error-message="Unspecified error") ->
  console.error error-message if error-code
  process.exit error-code

e, display <- x11.create-client!
if e
  exit 1 "Could not create X client."

X     = display.client
root  = display.screen[0].root

do
  # `node-ewmh` currently (bug) expects these atoms to be defined in
  # `node-x11`'s atom cache and fails if they aren't.

  atom-names = <[ WM_PROTOCOLS WM_DELETE_WINDOW ]>
  e, atom-values <- async.map do
    atom-names
    (atom-name, cb) ->
      X.InternAtom do
        false # create it if it doesn't exist
        atom-name
        cb

ewmh-client = new ewmh X, root

managed-data = {} # Indexed with X window ID
on-top-ids  = []

focus = root


<- fs.unlink "/tmp/wmstate.sock"
state-output = do
  clients = {}
  server = net.create-server!
    ..listen "/tmp/wmstate.sock"
    ..on \error -> console.error "Socket error: #it"
    ..on \connection (stream) ->
      console.log "New connection"

      # The file descriptors of socket connections are unique, so that's
      # something to use as a UUID key.
      stream-id = stream._handle.fd
      clients[stream-id] = stream
      stream
        ..on \close ->
          stream.end!
          delete clients[stream-id]
        ..on \error ->
          stream.end!
          delete clients[stream-id]

      # Send initial state
      for id,data of managed-data
        { x, y, width, height } = data
        stream.write JSON.stringify {
          action : \existing-add
          id : Number id
          x, y, width, height
        }
        stream.write \\n
  ->
    console.log "loggin" it
    for id, stream of clients
      stream
        ..write JSON.stringify it
        ..write \\n

action = do

  min-width  = 50
  min-height = 50

  move : (id, x, y) ->
    return if id is root
    e, geom <- X.Get-geometry id
    return Error "Could not get geometry of #id: #e" if e
    new-x = geom.x-pos + x
    new-y = geom.y-pos + y
    state-output action : \move id : id, x : new-x, y : new-y
    X.Move-window id, new-x, new-y
  resize : (id, x, y) ->
    return if id is root
    e, geom <- X.Get-geometry id
    return Error "Could not get geometry of #id: #e" if e
    new-width  = Math.max (geom.width + x), min-width
    new-height = Math.max (geom.height + y), min-height
    state-output action : \resize id : id, width : new-width, height : new-height
    X.Resize-window id, new-width, new-height
  focus : (id) ->
    X.Set-input-focus id
    state-output action : \focus id : id
    focus := id
  raise : (id) ->
    return if id is root
    state-output action : \raise id : id
    X.Configure-window id, { sibling : on-top-ids.0, stack-mode : 1 }
  forget : (id) ->
    return if id is root
    verbose-log "<-: #id"
    delete managed-data[id]
    state-output action : \destroy id : id
  destroy: (id) ->
    ewmh-client.close_window id, true # use delete protocol
  kill: (id) ->
    X.Kill-client id

  map : (id) -> X.Map-window id

manage = (id, cb=->) ->

  throw new Error "Null window ID" unless id? # Sanity
  e, attr <- X.Get-window-attributes id
  if e
    console.error "Error getting window attributes (wid #id): #e"
    return cb e
  if attr.override-redirect # Ignore pop-ups
    verbose-log "Ignoring #id"
    return cb null false

  verbose-log "->: #id"

  get-wm-class = (id, class-cb) ->
    e, prop <- X.Get-property 0 id, X.atoms.WM_CLASS, X.atoms.STRING, 0, 10000000
    return class-cb e if e
    switch prop.type
    | X.atoms.STRING =>
      # Data format:
      #
      #     progname<null>classname<null>
      #
      # where `<null>` is a null-character.
      null-char = String.from-char-code 0
      strings = prop.data.to-string!split null-char
      return class-cb null program : strings.0, class : strings.1
    | 0 => return class-cb null [ "" "" ] # No WM_CLASS set
    | _ => return class-cb "Unexpected non-string WM_CLASS"

  # Put Hudkit on top
  e, attr <- get-wm-class id
  if e
    console.error "Error getting window class (wid #id): #e"
    return cb e
  switch attr.class
  | \Hudkit   =>
    on-top-ids.push id
    return cb null false
  | otherwise =>
    # Subscribe to window entry events
    do
      event-mask = x11.event-mask.EnterWindow
      X.Change-window-attributes id, { event-mask }

    # Remember window with initial position and size
    e, geom <- X.Get-geometry id
    { x-pos : x, y-pos : y, width, height } = geom
    managed-data[id] = { x, y, width, height }
    state-output { action : \add id, x, y, width ,height }
    return cb null true



# ----------
# BEGIN MAIN
# ----------



action.focus root

drag =
  target : null
  start  : x : 0 y : 0

event-mask = x11.event-mask.StructureNotify
  .|. x11.event-mask.SubstructureNotify
  .|. x11.event-mask.SubstructureRedirect
X
  # To prevent race conditions with node-ewmh also changing the root window
  # attributes, we grab the server for the duration of that change.
  ..Grab-server!
  # Subscribe to events
  ..Get-window-attributes root, (e, attrs) ->
    throw e if e
    event-mask .|.= attrs.event-mask
    X.Change-window-attributes root, { event-mask }, (err) ->
      # This callback isn't called on success; only on error.
      # I think it's a bug, but let's roll with it for now.
      if err.error is 10
        exit 1 'Error: another window manager already running.'
  ..Ungrab-server!

  # Pick up previously mapped windows.  These must have been mapped by another
  # window manager instance previously.
  ..QueryTree root, (e, tree) -> tree.children.for-each ->
    X.Get-window-attributes it, (e, attrs) ->
      if attrs.map-state
        manage it

  ..on 'error' ->
    console.error it

  # Handle incoming events
  ..on 'event' (ev) ->
    switch ev.name
    | \MapRequest =>
      action.map ev.wid
      e, accepted <- manage ev.wid
      throw e if e
      if accepted
        action.raise ev.wid
        action.focus ev.wid
    | \ConfigureRequest =>
      #action.resize ev.wid, ev.width, ev.height
    | \DestroyNotify => fallthrough
    | \UnmapNotify =>
      action.forget ev.wid
      if focus is ev.wid
        action.focus root
    | \EnterNotify =>
      action.focus ev.wid
      #action.raise ev.wid
    | \MapNotify => # nothing
    | \CreateNotify => # nothing
    | \ClientMessage => # nothing
    | \ConfigureNotify =>
      if managed-data[ev.wid1]
        that{ x,y,width,height } = ev
    | otherwise => verbose-log "Unknown event type" ev

command = (line) ->
  args = line |> words
  return unless args.length
  switch args.shift!
  | \resize =>
    return if focus is root
    verbose-log "Moving #focus"
    x = args.shift! |> Number
    y = args.shift! |> Number
    action.resize focus, x, y
  | \move =>
    return if focus is root
    verbose-log "Moving #focus"
    x = args.shift! |> Number
    y = args.shift! |> Number
    console.log focus, typeof! focus
    action.move focus, x, y
  | \move-all =>
    ids = keys managed-data
          .map Number # because `keys` returns strings
    return unless ids.length
    verbose-log "Moving #focus"
    x = args.shift! |> Number
    y = args.shift! |> Number
    # Move every window
    # (In parallel for efficiency)
    async.each do
      ids
      (item, cb) ->
        action.move item, x, y
        cb!
      -> # We don't care when it finishes.
  | \pointer-resize =>
    return if focus is root
    verbose-log "Resizing #focus"
    x = args.shift! |> Number
    y = args.shift! |> Number
    if drag.target is null
      drag
        ..target  = focus
        ..start.x = x
        ..start.y = y
    delta-x   = x - drag.start.x
    delta-y   = y - drag.start.y
    drag.start
      ..x = x
      ..y = y
    action.resize drag.target, delta-x, delta-y
  | \pointer-move =>
    return if focus is root
    verbose-log "Pointer-moving #focus"
    x = args.shift! |> Number
    y = args.shift! |> Number
    if drag.target is null
      drag
        ..target = focus
        ..start.x = x
        ..start.y = y
    delta-x   = x - drag.start.x
    delta-y   = y - drag.start.y
    verbose-log "Moving #{drag.target} by #delta-x,#delta-y"
    drag.start
      ..x = x
      ..y = y
    action.move drag.target, delta-x, delta-y
  | \pointer-move-all =>
    ids = keys managed-data .map Number
    return unless ids.length
    x = args.shift! |> Number
    y = args.shift! |> Number
    if drag.start.x is null
      drag.start
        ..x = x
        ..y = y
    delta-x   = (x - drag.start.x) * 3
    delta-y   = (y - drag.start.y) * 3
    verbose-log "Moving all by #delta-x,#delta-y"
    drag.start
      ..x = x
      ..y = y
    # Move every window
    # (In parallel for efficiency)
    async.each do
      ids
      (item, cb) ->
        action.move item, delta-x, delta-y
        cb!
      -> # We don't care when it finishes.
  | \reset =>
    verbose-log "RESET"
    drag
      ..target = null
      ..start
        ..x = null
        ..y = null
  | \raise =>
    verbose-log "Raising #focus"
    action.raise focus
  | \pointer-raise =>
    # Find and raise the window under the pointer
    e, res <- X.Query-pointer root
    throw e if e
    { child } = res
    return unless child # Ignore clicks on root window
    verbose-log "Raising #child"
    action.raise child
  | \kill =>
    verbose-log "Killing #focus"
    action.kill focus
  | \destroy =>
    verbose-log "Destroying #focus"
    action.destroy focus
  | \exit =>
    exit!
  | otherwise =>
    console.log "Didn't understand command `#line`"

(if argv.command-file
  (spawn \tail [ \-F argv.command-file ]).stdout
else process.stdin)
  .pipe split \\n .on \data (line) -> command line

exec "cd /home/an/code/hud; ./index.ls"
