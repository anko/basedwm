require! <[ fs net split async ]>
wm-kit = require \../wm-kit.js
{ words } = require \prelude-ls
{ spawn } = require \child_process
{ mkfifo-sync } = require \mkfifo
_ = require \highland

argv = require \yargs .argv

verbose-log = if argv.verbose then console.log else -> # no-op

e, wm <- wm-kit!
throw e if e

windows = []
focus = wm.root

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
      windows.for-each (window) ->
        e, { x, y, width, height } <- window.get-geometry!
        stream.write JSON.stringify {
          action : \existing-add
          id : Number window.id
          x, y, width, height
        }
        stream.write \\n
  ->
    console.log "loggin" it
    for id, stream of clients
      stream
        ..write JSON.stringify it
        ..write \\n

focus-on = (window) ->
  focus := window
    ..set-input-focus!
  state-output action : \focus id : window.id

on-top-windows = []

consider-managing = (window) ->
  e, attr <- window.get-attributes!
  throw e if e

  if not attr.override-redirect # don't pick up popups

    e, wm-class <- window.get-wm-class!

    if wm-class.class is \Hudkit
      window.raise-to-below on-top-windows.0
      on-top-windows.push window

    else
      windows.push window

      window.subscribe-to \EnterWindow

      e, { x, y, width, height } <- window.get-geometry!
      throw e if e
      state-output {
        action : \add
        id : window.id
        x, y, width, height
      }

      window.raise-to-below on-top-windows.0
      window.set-input-focus!
      focus-on window

# Pick up existing mapped windows and manage them if necessary
wm .all-windows (e, wins) ->
  throw e if e
  w <- wins.for-each
  e, attr <- w.get-attributes!
  throw e if e
  if attr.map-state then consider-managing w

_ wm.interaction-stream
  #.filter -> windows.some (.id == it)
  .each state-output

wm.event-stream .on \data ({ type, window }) ->
  switch type
  | \MapRequest =>
    e <- window.map!
    throw e if e
    consider-managing window
  | \ConfigureRequest => # ignore
    # action.resize ev.wid, ev.width, ev.height
  | \DestroyNotify => fallthrough
  | \UnmapNotify =>
    for i til windows.length
      if windows[i].id is window.id
        windows.splice i, 1
        break
    if focus.id is window.id
      verbose-log "focusing root"
      focus-on wm.root
  | \EnterNotify => focus-on window
  | \ClientMessage => # nothing

commands = do

  drag =
    target : null
    start  : x : 0 y : 0
  drag-update = (x, y, target) ->
    drag
      ..target = target if target
      ..start
        ..x = x
        ..y = y
  drag-reset = ->
    drag
      ..target = null
      ..start
        ..x = null
        ..y = null

  commands = {}

  specify = (name, ...types, action) ->
    commands[name] = (args) ->
      if args.length isnt types.length
        return console.error "Invalid number of arguments to command #name"
      args-converted = []
      for a,i in args
        try
          converted-arg = global[types[i]] a
          args-converted.push converted-arg
        catch e
          console.error "Could not interpret #a as #{types[i]}"
      action.apply null args-converted

  specify \resize \Number \Number ->
    return if focus.id is root.id
    focus.resize-by &0, &1
  specify \move   \Number \Number ->
    return if focus.id is root.id
    focus.move-by &0, &1
  specify \move-all \Number \Number (x, y) ->
    return unless windows.length
    async.each do
      windows
      (w, cb) -> w.move-by x, y, cb
      -> # We don't care when it finishes, or about errors.
  specify \pointer-resize \Number \Number (x, y) ->
    return if focus.id is root.id
    if drag.target is null then drag-update x, y, focus
    delta-x = x - drag.start.x
    delta-y = y - drag.start.y
    drag-update x, y
    drag.target.resize-by delta-x, delta-y
  specify \pointer-move \Number \Number (x, y) ->
    return if focus.id is root.id
    if drag.target is null then drag-update x, y, focus
    delta-x   = x - drag.start.x
    delta-y   = y - drag.start.y
    drag-update x, y
    drag.target.move-by delta-x, delta-y
  specify \pointer-move-all \Number \Number (x, y) ->
    return if focus.id is root.id
    if drag.start.x is null then drag-update x, y
    delta-x   = (x - drag.start.x) * 3
    delta-y   = (y - drag.start.y) * 3
    verbose-log "Moving all by #delta-x,#delta-y"
    drag-update x, y
    async.each do
      windows
      (w, cb) -> w.move-by delta-x, delta-y, cb
      -> # We don't care when it finishes, or about errors.
        specify \reset ->
  specify \reset -> drag-reset!
  specify \raise -> focus.raise-to-below on-top-windows.0
  specify \pointer-raise -> # Find and raise the window under the pointer
    e, w <- wm.window-under-pointer!
    throw e if e
    if w then w.raise-to-below on-top-windows.0
  specify \kill -> focus.kill!
  specify \destroy -> focus.close!
  specify \exit -> process.exit!

  commands # return

run-command = (line) ->
  args = line |> words
  return unless args.length
  command-name = args.shift!
  if commands[command-name]
    that args
  else console.error "No such command: #command-name"

input-stream = do

  mkfifo-stream = (path) ->
    if fs.exists-sync path then fs.unlink-sync path
    mkfifo-sync path, 8~600
    (spawn \tail [ \-F path ]).stdout

  switch argv.command-file
  | \- => process.stdin
  | true => fallthrough
  | undefined => mkfifo-stream "/tmp/basedwm#{process.env.DISPLAY}-cmd.fifo"
  | otherwise => mkfifo-stream that

input-stream .pipe split \\n .on \data (line) -> run-command line
