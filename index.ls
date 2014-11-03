#!/usr/bin/env lsc
require! x11

var X, root, white
frames = {}

manage-window = (id) ->
  console.log "MANAGE WINDOW: #id"
  X.Map-window id
  e, attrs <- X.Get-window-attributes id
  if attrs.8 # override-redirect flag
    console.log "don't manage"
    return

  X.Change-save-set 1, id

  #X.Get-geometry id, (err, geom) ->
  #  console.log "window geometry: ", geom

client = x11.create-client (err, display) ->
  X := display.client

  root := display.screen[0].root
  white := display.screen[0].white_pixel
  console.log "root=#root"
  event-mask = x11.event-mask.StructureNotify
  .|. x11.event-mask.SubstructureNotify
  .|. x11.event-mask.SubstructureRedirect
  X.Change-window-attributes root, { event-mask }, (err) ->
    if err.error == 10
      console.error 'Error: another window manager already running.'
      process.exit 1
  X.QueryTree root, (err, tree) ->
    tree.children.for-each manage-window

event-type =
  map-request : 20
  configure-request : 23
  expose : 12

client
  ..on 'error' -> console.error it
  ..on 'event' (ev) ->
    console.log ev
    switch ev.type
    | event-type.map-request =>
        manage-window ev.wid unless frames[ev.wid]
    | event-type.configure-request =>
        X.ResizeWindow ev.wid, ev.width, ev.height
