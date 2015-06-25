require! <[ x11 ewmh async ]>
_ = require \highland

wrap-display = (display) ->

  X           = display.client
  root-window = display.screen.0.root

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

  ewmh-client = new ewmh X, root-window

  window-data = {}

  interaction-stream = _!

  init-window-data = (id) !->
    # Remember initial geometry
    e, geom <- X.Get-geometry id
    { x-pos : x, y-pos : y, width, height } = geom
    window-data[id] = geometry : { x, y, width, height }

  event-mask = x11.event-mask.StructureNotify
    .|. x11.event-mask.SubstructureNotify
    .|. x11.event-mask.SubstructureRedirect
    .|. x11.event-mask.FocusChange

  X
    # To prevent race conditions with node-ewmh also changing the root window
    # attributes, we grab the server for the duration of that change.
    ..Grab-server!
    # Subscribe to events
    ..Get-window-attributes root-window, (e, attrs) ->
      throw e if e
      event-mask .|.= attrs.event-mask
      X.Change-window-attributes root-window, { event-mask }, (err) ->
        # This callback isn't called on success; only on error.  I think it's a
        # bug, but let's roll with it for now.
        if err.error is 10
          exit 1 'Error: another window manager already running.'
    ..Ungrab-server!

    # Pick up previously mapped windows.  These must have been mapped by
    # another window manager instance previously.
    ..QueryTree root-window, (e, tree) ->
      tree.children.for-each init-window-data

  wrap-window = (id) ->

    map = (cb=->) -> X.Map-window id ; cb!

    get-geometry = (cb=->) ->
      if window-data[id]?geometry
        cb null that
      else
        e, geom <- X.Get-geometry id
        return cb e if e
        { x-pos : x, y-pos : y, width, height } = geom
        window-data[id] =
          geometry : { x, y, width, height }

        # Cache it
        if not window-data[id] then window-data[id] = {}
        window-data[id].geometry{ x-pos : x, y-pos : y, width, height } = geom

        cb null window-data[id].geometry

    get-attributes = (cb=->) -> X.Get-window-attributes id, cb

    move-to = (x, y, cb=->) ->
      interaction-stream.write { action : \move id, x, y }
      X.Move-window id, x, y ; cb!
      window-data[id].geometry
        ..x = x
        ..y = y

    resize-to = (x, y, cb=->) ->
      X.Resize-window id, x, y ; cb!
      window-data[id].geometry
        ..width = x
        ..height = y
      interaction-stream.write action : \resize id : id, width : x, height : y

    move-by = (dx, dy, cb=->) ->
      e, geom <- get-geometry!
      if e then return cb e
      { x, y } = geom
      new-x = x + dx
      new-y = y + dy
      X.Move-window id, new-x, new-y
      window-data[id].geometry
        ..x = new-x
        ..y = new-y
      interaction-stream.write action : \move id : id, x : new-x, y : new-y
      cb!

    resize-by = (dx, dy, cb=->) ->
      e, geom <- get-geometry!
      if e then return cb e
      { width, height } = geom
      if e then return cb e
      new-w = width + dx
      new-h = height + dy
      X.Resize-window id, new-w, new-h
      window-data[id].geometry
        ..width  = new-w
        ..height = new-h
      interaction-stream.write do
        action : \resize id, width : new-w, height : new-h
      cb!

    set-input-focus = (cb=->) -> X.Set-input-focus id ; cb!

    raise-to-below = (sibling-window, cb=->) ->
      X.Configure-window id, { sibling : sibling-window?id, stack-mode : 1 }
      cb!

    close = (cb=->) -> ewmh-client.close_window id, true ; cb!

    kill = (cb=->) -> X.Kill-client id ; cb!

    subscribe-to = (event-names, cb=->) ->
      if typeof! event-names isnt \Array
        event-names := [ event-names ]

      event-mask = event-names.map (x11.event-mask.) .reduce (.|.), 0
      X.Change-window-attributes id, { event-mask }

    get-wm-class = (cb=->) ->
      e, prop <- X.Get-property 0 id, X.atoms.WM_CLASS, X.atoms.STRING, 0, 1000000
      return cb e if e
      switch prop.type
      | X.atoms.STRING =>

        # Data format:
        #
        #     progname<null>classname<null>
        #
        # where `<null>` is a null-character.

        null-char = String.from-char-code 0
        strings   = prop.data .to-string! .split null-char
        cb null program : strings.0, class : strings.1

      | 0 => cb null [ "" "" ] # No WM_CLASS set
      | _ => cb "Unexpected non-string WM_CLASS"

    return {
      id, map, get-geometry, get-attributes, move-to, resize-to, move-by,
      resize-by, set-input-focus, raise-to-below, close, kill, subscribe-to,
      get-wm-class
    }

  wrap-event = ->
    type : it.name, window : wrap-window it.wid

  actions =
    ConfigureRequest : ->
      init-window-data it.wid
    ConfigureNotify : ->
      if window-data[it.wid] then that.geometry{ x, y, width, height } = it
    DestroyNotify : ->
      interaction-stream.write action : \destroy id : it.wid
      delete window-data[it.wid]

  #interesting-events = <[
  #  ConfigureNotify
  #  ConfigureRequest
  #  DestroyNotify
  #  EnterNotify
  #  MapRequest
  #  UnmapNotify
  #]>

  X.on \error -> console.error it

  root : wrap-window root-window
  interaction-stream : interaction-stream
  event-stream : _ \event X
    .map ->
      if actions[it.name] then that it
      return it
    #.filter (.name in interesting-events)
    .map wrap-event
  window-under-pointer : (cb) ->
    e, res <- X.Query-pointer root-window
    if e then return cb e
    cb null wrap-window res.child

module.exports = (cb) ->
  e, display <- x11.create-client!
  cb e, wrap-display display
