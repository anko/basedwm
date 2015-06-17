# basedwm ![](https://img.shields.io/badge/stability-experimental-red.svg?style=flat-square)

Minimalistic [X window manager][1] in [LiveScript][2], with an infinite panning
desktop.  Controlled by [named pipe][3].  Emits focus events and window
positions on a [socket][4].

## Install

You only need [Node.js][5] (or [io.js][6]) to run the basic WM.

      sudo npm i -g basedwm

Then add `exec basedwm` to your `~/.xinitrc`, commenting out any existing WM.

However, note that basedwm alone doesn't provide any keyboard or pointer
controls or window decorations.  Instead, it takes control input from a named
pipe and logs focus events and window positions out to another named pipe.
This way you can easily switch out what programs you use to control it or to
render window decorations.

## Keyboard controls

### Recommendations

To bind commands to keyboard controls, I recommend [sxhkd][7].  A suitable
example config is in [`example/basedwm.sxhkdrc`][8].

### Details

Basedwm is controlled through a named pipe, by default at
`/tmp/basedwm:0-cmd.fifo` (where the `:0` is the contents of the `$DISPLAY`
[env variable][9]).  The program `basedc` is provided for convenience; it just
echoes its arguments into that pipe.

Some commands are **stateless** and run immediately:

| name          | description                                              |
| ------------- | -------------------------------------------------------- |
| exit          | terminates the program                                   |
| raise         | raises the currently focused window                      |
| pointer-raise | raises window under pointer                              |
| move x y      | moves the currently focused window by the given amount   |
| move-all x y  | moves all windows, effectively panning the desktop       |
| resize x y    | resizes the currently focused window by the given amount |
| destroy       | closes the currently focused window (polite suggestion)  |
| kill          | kills the currently focused window (force close)         |

So `basedc move-all 50 -50` to move all windows 50px right and 50px up.

The **stateful** ones are intended for pointer interaction:

| name                 | description                             |
| -------------------- | --------------------------------------- |
| pointer-move x y     | moves focused window with pointer       |
| pointer-resize x y   | resizes focused window with the pointer |
| pointer-move-all x y | pans desktop with pointer               |
| reset                | resets pointer drag state               |

Remember to send a `reset` once each drag is done!  This tells basedwm that the
next pointer command will be a separate action.

## Window decorations

### Recommendations

[Hudkit][10] was written for this.  I'll get around to uploading my setup
eventually, but the basic idea is to create a Node server that `net.connect`s
to the WM state socket, dumps the events into a websocket and serves up a page
that uses [D3][11] to render borders and a minimap.  [Screenshot here][12].

<!-- TODO publish a more complete hud example -->

### Details

Basedwm outputs window positions on a socket in `/tmp/wmstate.sock`, as
newline-delimited [JSON][13] objects.  Every object has a property `id` with
the window's ID, and a property `action` representing the event type.

The possible `action`s and their additional properties are:

| action       | description             | additional properties       |
| ------------ | ----------------------- | --------------------------- |
| focus        | window gained focus     | none                        |
| destroy      | window was destroyed    | none                        |
| existing-add | initial window position | `x`, `y`, `width`, `height` |
| add          | window was added        | `x`, `y`, `width`, `height` |
| move         | window was moved        | `x`, `y`                    |
| resize       | window was resized      | `width`, `height`           |

`existing-add`-events are only sent immediately after connecting.  This lets
any consuming program initialise its copy of the window positions.

The `x` and `y` properties indicate the absolute coordinates of the window's
top-left corner, relative to the screen's top-left corner.  The `width` and
`height` properties indicate the absolute dimensions of the window.

You can easily survey the output using `socat UNIX:/tmp/wmstate.sock -`.

## Bugs

Yes.

## Inspirations & thankyous

Intended as a modern reinterpretation of [swm][14], with the big virtual
desktop taken to the extreme.  Exposing controls on a pipe/socket interface and
outsourcing controls to [sxhkd][15] are ideas from [bspwm][16].

## License

[ISC][17].

[1]: https://en.wikipedia.org/wiki/X_window_manager
[2]: http://livescript.net
[3]: http://en.wikipedia.org/wiki/Named_pipe
[4]: https://en.wikipedia.org/wiki/Unix_domain_socket
[5]: https://nodejs.org/
[6]: https://iojs.org/
[7]: https://github.com/baskerville/sxhkd
[8]: example/basedwm.sxhkdrc
[9]: https://en.wikipedia.org/wiki/Environment_variable
[10]: https://github.com/anko/hudkit
[11]: http://d3js.org/
[12]: https://cloud.githubusercontent.com/assets/5231746/8208678/c40d95a6-1500-11e5-9ecf-84aece17044e.png
[13]: http://json.org/
[14]: https://en.wikipedia.org/wiki/Swm
[15]: https://github.com/baskerville/sxhkd
[16]: https://github.com/baskerville/bspwm
[17]: LICENSE
