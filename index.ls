#!/usr/bin/env lsc
require! <[ x11 split ]>
{ words } = require \prelude-ls

e, display <- x11.create-client!

X     = display.client
root  = display.screen[0].root

drag =
  target : null
  start  : x : 0 y : 0

focus = null

set-focus = (id) ->
  focus := id
  X.Set-input-focus id

get-class = (id, cb) ->
  X.Get-property 0 id, X.atoms.WM_CLASS, X.atoms.STRING, 0, 1000000, (e, prop) ->
    cb e if e
    if prop.type = X.atoms.STRING # just in case
      return cb null prop.data.to-string!
    else cb "Unexpected non-string WM_CLASS"

move-all-by = (x, y) ->
  e, tree <- X.Query-tree root
  id <- tree.children.for-each
  e, geom <- X.Get-geometry id
  X.Move-window id, geom.x-pos + x, geom.y-pos + y

move-by = (id, x, y) ->
  e, geom <- X.Get-geometry id
  new-x  = geom.x-pos + x
  new-y = geom.y-pos + y
  X.Move-window id, new-x, new-y

resize-by = (id, x, y) ->
  e, geom <- X.Get-geometry id
  new-width  = Math.max (geom.width + x), 50
  new-height = Math.max (geom.height + y), 50
  X.Resize-window id, new-width, new-height

manage-window = (id) ->
  console.log "->: #id"
  X.Map-window id
  e, attrs <- X.Get-window-attributes id

  return if attrs.override-redirect # Leave pop-ups alone

  e, class-name <- get-class id # Leave Hudkit alone
  return if e or class-name is \Hudkit

  event-mask = x11.event-mask.EnterWindow
  X.Change-window-attributes id, { event-mask }
  X.Set-input-focus id

unmanage-window = (id) ->
  console.log "<-: #id"
  # If there's something we need to forget about this window, do it.
  if focus is id
    focus := null

X
  # Subscribe to events
  event-mask = x11.event-mask.StructureNotify
    .|. x11.event-mask.SubstructureNotify
    .|. x11.event-mask.SubstructureRedirect
  ..Change-window-attributes root, { event-mask }, (err) ->
    # This callback isn't called on success; only on error.
    # I think it's a bug, but let's roll with it for now.
    if err.error is 10
      console.error 'Error: another window manager already running.'
      process.exit 1

  # Pick up existing windows
  ..QueryTree root, (e, tree) -> tree.children.for-each manage-window

  ..on 'error' -> console.error it

  # Handle incoming events
  ..on 'event' (ev) ->
    type =
      enter-notify : 7
      expose : 12
      create-notify : 16
      destroy-notify : 17
      unmap-notify : 18
      map-notify : 19
      map-request : 20
      configure-request : 23
    #console.log ev
    switch ev.type
    | type.map-request       => manage-window ev.wid
    | type.configure-request =>
      break if ev.wid is root # Refuse to resize root window
      #console.log ev
      #moveresize ev.wid, ev.width, ev.height
      #X.ResizeWindow ev.wid, ev.width, ev.height
    | type.destroy-notify    => unmanage-window ev.wid
    | type.enter-notify      => set-focus ev.wid

process.stdin .pipe split \\n
  .on \data (line) ->
    args = line |> words
    #console.log args
    return unless args.length
    switch args.shift!
    | \resize =>
      console.log "Resizing #focus"
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
      resize-by drag.target, delta-x, delta-y
    | \move =>
      console.log "Moving #focus"
      x = args.shift! |> Number
      y = args.shift! |> Number
      if drag.target is null
        drag
          ..target = focus
          ..start.x = x
          ..start.y = y
      delta-x   = x - drag.start.x
      delta-y   = y - drag.start.y
      console.log "Moving #{drag.target} by #delta-x,#delta-y"
      drag.start
        ..x = x
        ..y = y
      move-by drag.target, delta-x, delta-y
    | \move-all =>
      x = args.shift! |> Number
      y = args.shift! |> Number
      if drag.start.x is null
        drag.start
          ..x = x
          ..y = y
      delta-x   = (x - drag.start.x) * 5
      delta-y   = (y - drag.start.y) * 5
      console.log "Moving all by #delta-x,#delta-y"
      drag.start
        ..x = x
        ..y = y
      move-all-by delta-x, delta-y
    | \reset =>
      console.log "RESET"
      drag
        ..target = null
        ..start
          ..x = null
          ..y = null
