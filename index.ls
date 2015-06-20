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

_ wm.interaction-stream
  #.filter -> windows.some (.id == it)
  .each state-output

wm.event-stream .on \data ({ type, window }) ->
  switch type
  | \MapRequest =>
    e <- window.map!
    throw e if e
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

drag =
  target : null
  start  : x : 0 y : 0

command = (line) ->
  args = line |> words
  return unless args.length
  switch args.shift!
  | \resize =>
    return if focus.id is root.id
    verbose-log "Moving #focus"
    x = args.shift! |> Number
    y = args.shift! |> Number
    focus.resize-by x, y
  | \move =>
    return if focus.id is root.id
    verbose-log "Moving #focus"
    x = args.shift! |> Number
    y = args.shift! |> Number
    focus.move-by x, y
  | \move-all =>
    return unless windows.length
    verbose-log "Moving #focus"
    x = args.shift! |> Number
    y = args.shift! |> Number
    # Move every window
    # (In parallel for efficiency)
    async.each do
      windows
      (w, cb) ->
        w.move-by x, y, cb
      -> # We don't care when it finishes, or about errors.
  | \pointer-resize =>
    return if focus.id is root.id
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
    drag.target.resize-by delta-x, delta-y
  | \pointer-move =>
    return if focus.id is root.id
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
    drag.target.move-by delta-x, delta-y
  | \pointer-move-all =>
    return if focus.id is root.id
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
    async.each do
      windows
      (w, cb) -> w.move-by delta-x, delta-y, cb
      -> # We don't care when it finishes, or about errors.
  | \reset =>
    verbose-log "RESET"
    drag
      ..target = null
      ..start
        ..x = null
        ..y = null
  | \raise =>
    verbose-log "Raising #focus"
    focus.raise-to-below on-top-windows.0
  | \pointer-raise =>
    # Find and raise the window under the pointer
    e, w <- wm.window-under-pointer!
    throw e if e
    if w
      verbose-log "Raising #w"
      w.raise-to-below on-top-windows.0
  | \kill =>
    verbose-log "Killing #focus"
    focus.kill!
  | \destroy =>
    verbose-log "Destroying #focus"
    focus.close!
  | \exit => process.exit!
  | otherwise =>
    console.error "Didn't understand command `#line`"

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

input-stream .pipe split \\n .on \data (line) -> command line
