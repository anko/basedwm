#!/usr/bin/env lsc
require! x11

e, display <- x11.create-client!

X     = display.client
root  = display.screen[0].root

manage-window = (id) ->
  console.log "->: #id"
  X.Map-window id
  e, attrs <- X.Get-window-attributes id
  return if attrs.override-redirect # Leave pop-ups alone

unmanage-window = (id) ->
  console.log "<-: #id"
  # If there's something we need to forget about this window, do it.

X
  event-mask = x11.event-mask.StructureNotify
    .|. x11.event-mask.SubstructureNotify
    .|. x11.event-mask.SubstructureRedirect
  ..Change-window-attributes root, { event-mask }, (err) ->
    if err.error is 10
      console.error 'Error: another window manager already running.'
      process.exit 1

  ..QueryTree root, (e, tree) -> tree.children.for-each manage-window

  ..on 'error' -> console.error it
  ..on 'event' (ev) ->
    type =
      map-request : 20
      destroy-notify : 17
      configure-request : 23
      expose : 12
    switch ev.type
    | type.map-request       => manage-window ev.wid
    | type.configure-request => X.ResizeWindow ev.wid, ev.width, ev.height
    | type.destroy-notify    => unmanage-window ev.wid
