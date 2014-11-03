#!/usr/bin/env lsc
require! x11

e, display <- x11.create-client!

X     = display.client
root  = display.screen[0].root
console.log "root=#root"
frames = {}

manage-window = (id) ->
  console.log "MANAGE WINDOW: #id"
  X.Map-window id
  e, attrs <- X.Get-window-attributes id
  if attrs.override-redirect
    # This is a pop-up of some sort; don't redirect anything.
    return

  #X.Change-save-set 1, id

  #X.Get-geometry id, (err, geom) ->
  #  console.log "window geometry: ", geom

event-mask = x11.event-mask.StructureNotify
  .|. x11.event-mask.SubstructureNotify
  .|. x11.event-mask.SubstructureRedirect
X.Change-window-attributes root, { event-mask }, (err) ->
  if err.error is 10
    console.error 'Error: another window manager already running.'
    process.exit 1
X.QueryTree root, (err, tree) ->
  tree.children.for-each manage-window

X
  ..on 'error' -> console.error it
  ..on 'event' (ev) ->
    type =
      map-request : 20
      destroy-notify : 17
      configure-request : 23
      expose : 12
    console.log ev
    switch ev.type
    | type.map-request       => manage-window ev.wid unless frames[ev.wid]
    | type.configure-request => X.ResizeWindow ev.wid, ev.width, ev.height
    | type.destroy-notify    => delete frames[ev.wid]
