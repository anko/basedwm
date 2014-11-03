#!/usr/bin/env lsc
require! x11

var X, root, white
frames = {}
drag-start = null

ManageWindow = (wid) ->
  console.log "MANAGE WINDOW: #wid"
  X.GetWindowAttributes wid, (err, attrs) ->
    if attrs.8 # override-redirect flag
      # don't manage
      console.log "don't manage"
      X.MapWindow wid
      return

    var winX, winY
    winX = parseInt (Math.random! * 300)
    winY = parseInt (Math.random! * 300)

    X.GetGeometry wid, (err, clientGeom) ->

      console.log "window geometry: ", clientGeom
      width  = clientGeom.width
      height = clientGeom.height
      X.ChangeSaveSet 1, wid
      X.MapWindow wid

client = x11.createClient (err, display) ->
  X := display.client
  e, Render <- X.require \render
  X.Render = Render

  root := display.screen[0].root
  white := display.screen[0].white_pixel
  console.log "root=#root"
  event-mask = x11.event-mask.StructureNotify
  .|. x11.eventMask.SubstructureNotify
  .|. x11.eventMask.SubstructureRedirect
  .|. x11.eventMask.Exposure
  X.ChangeWindowAttributes root, { event-mask }, (err) ->
    if err.error == 10
      console.error 'Error: another window manager already running.'
      process.exit 1
  X.QueryTree root, (err, tree) ->
    tree.children.for-each ManageWindow

  X.bggrad = X.AllocID!
  Render.LinearGradient X.bggrad, [-10,0], [0,1000],
    #RenderRadialGradient(pic_grad, [0,0], [1000,100], 10, 1000,
    #RenderConicalGradient(pic_grad, [250,250], 360,
        [
          [0,   [0,0,0,0xffffff ] ],
          #[0.1, [0xfff, 0, 0xffff, 0x1000] ] ,
          #[0.25, [0xffff, 0, 0xfff, 0x3000] ] ,
          #[0.5, [0xffff, 0, 0xffff, 0x4000] ] ,
          [1,   [0xffff, 0xffff, 0, 0xffffff] ]
        ]

  X.rootpic = X.AllocID!
  Render.CreatePicture X.rootpic, root, Render.rgb24

event-type =
  map-request : 20
  configure-request : 23
  expose : 12

client
  ..on 'error' -> console.error it
  ..on 'event' (ev) ->
    console.log ev
    switch ev.type
    | event-type.map-request
      if not frames[ev.wid]
        ManageWindow ev.wid
      return
    | event-type.configure-request
        X.ResizeWindow ev.wid, ev.width, ev.height
    | event-type.expose
      console.log 'EXPOSE', ev
      X.Render.Composite 3, X.bggrad, 0, X.rootpic, 0, 0, 0, 0, 0, 0, 1000, 1000
