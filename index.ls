#!/usr/bin/env lsc
require! x11

e, display <- x11.create-client!

X     = display.client
root  = display.screen[0].root

move-resize = (id, x, y, width, height) ->
  X.Configure-window id, { x, y, width, height }

move-all-by = (x, y) ->
  e, tree <- X.Query-tree root
  id <- tree.children.for-each
  e, geom <- X.Get-geometry id
  X.Move-window id, geom.x-pos + x, geom.y-pos + y

manage-window = (id) ->
  console.log "->: #id"
  X.Map-window id
  e, attrs <- X.Get-window-attributes id
  return if attrs.override-redirect # Leave pop-ups alone

unmanage-window = (id) ->
  console.log "<-: #id"
  # If there's something we need to forget about this window, do it.

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
      expose : 12
      create-notify : 16
      destroy-notify : 17
      unmap-notify : 18
      map-notify : 19
      map-request : 20
      configure-request : 23
    console.log ev
    switch ev.type
    | type.map-request       => manage-window ev.wid
    | type.configure-request =>
      break if ev.wid is root # Refuse to resize root window
      console.log ev
      moveresize ev.wid, ev.width, ev.height
      X.ResizeWindow ev.wid, ev.width, ev.height
    | type.destroy-notify    => unmanage-window ev.wid
