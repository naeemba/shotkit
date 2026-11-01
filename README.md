# shotkit

Screenshots for wlroots-based Wayland compositors (Hyprland, Sway, river, ...),
built on grim and slurp. One command takes the shot, saves it, copies it to the
clipboard and shows a notification you can act on. It also does scrolling
captures: pick a region, scroll the page by hand, get one tall image.

```
shotkit region   # drag a region (the default)
shotkit output   # the focused monitor
shotkit full     # every monitor
shotkit scroll   # a scrolling capture of a region
```

## Features

- **Region, output and full-screen shots**, saved as PNG and copied to the
  clipboard. A region can span several monitors.
- **An actionable notification** after every shot: Edit (also a click on the
  notification), Copy, Folder and Delete. It is a plain `notify-send` with
  actions, so any notification daemon that supports actions works: mako,
  swaync, dunst, a Quickshell or AGS shell.
- **Edit in Satty**: the edit is saved over the same file and copied again,
  and the notification comes back for the edited image.
- **Scrolling capture**: the region stays outlined, with a small bar offering
  Start and Cancel. Start (Enter, or the same shortcut again), scroll, then Stop
  (the bar's button, or the shortcut again). The frames are stitched into one
  image, coping with sticky headers and footers, fixed sidebars, scrollbars,
  blinking cursors and translucent windows. The outline and bar are drawn
  outside the region, so they never end up in the image.

## Dependencies

Required: `bash`, `grim`, `slurp`, `wl-clipboard`, `libnotify` (0.7.12 or
later, for `--action`), `python` with `pillow` (for scrolling captures), `jq`
(for the focused output lookup).

Optional:

- `quickshell`, for the scrolling capture's outline and Start/Stop bar. It runs
  as its own instance from `share/shotkit/overlay`, so it needs no shell config
  of yours. Without it the capture still works: a notification tells you to
  press the shortcut again to start and to stop.
- `satty`, for the Edit button.
- `xdg-utils` (Folder) and `glib2` (`gio trash`, Delete).

On Arch:

```
pacman -S grim slurp wl-clipboard libnotify python-pillow jq quickshell satty
```

## Install

```
make install                 # to /usr/local, needs root
make install PREFIX=~/.local # for your user only; ~/.local/bin must be on PATH
make uninstall               # same PREFIX as the install
```

`DESTDIR` is honoured for packaging. An Arch `PKGBUILD` is in
`packaging/aur/`.

## Configuration

Environment variables, or the same names in `$XDG_CONFIG_HOME/shotkit/config`
(a shell snippet that is sourced, so anything it sets wins over the
environment):

| Variable             | Default                                    |
| -------------------- | ------------------------------------------ |
| `SHOTKIT_DIR`        | `$XDG_PICTURES_DIR/Screenshots`, else `~/Pictures/Screenshots` |
| `SHOTKIT_SLURP_ARGS` | `-d -b #1e1e2e66 -c #b4befeff -s #00000000 -w 2` |
| `SHOTKIT_SCROLL_KEY` | `the shortcut`, the name shown in the scrolling bar |

Example `~/.config/shotkit/config`:

```sh
SHOTKIT_DIR=~/Desktop
SHOTKIT_SCROLL_KEY="Super+Shift+P"
```

Satty reads its own `~/.config/satty/config.toml`. For a quick markup flow,
something like:

```toml
[general]
early-exit = true
initial-tool = "arrow"
copy-command = "wl-copy"
actions-on-enter = ["save-to-clipboard", "save-to-file", "exit"]
actions-on-escape = ["exit"]
disable-notifications = true
```

## Keybinds

Hyprland, Lua config:

```lua
hl.bind("SUPER + P",         hl.dsp.exec_cmd("shotkit region"))
hl.bind("SUPER + CTRL + P",  hl.dsp.exec_cmd("shotkit output"))
hl.bind("SUPER + SHIFT + P", hl.dsp.exec_cmd("shotkit scroll"))
hl.bind("Print",             hl.dsp.exec_cmd("shotkit region"))
hl.bind("SHIFT + Print",     hl.dsp.exec_cmd("shotkit full"))
```

Hyprland, hyprlang config:

```
bind = SUPER, P, exec, shotkit region
bind = SUPER CTRL, P, exec, shotkit output
bind = SUPER SHIFT, P, exec, shotkit scroll
bind = , Print, exec, shotkit region
bind = SHIFT, Print, exec, shotkit full
```

Sway:

```
bindsym $mod+p exec shotkit region
bindsym $mod+Shift+p exec shotkit scroll
bindsym Print exec shotkit full
```

Bind `scroll` to a single shortcut: pressing it again while a capture waits
starts it, and once more stops it.

## Known limits

- Scrolling capture is downward only. Scrolling back up is ignored until the
  page is below the last kept frame again.
- Scrolling faster than a frame (less than a fifth of the region overlapping)
  skips frames; the notification says how many were left out.
- A large animated area inside the region makes frames unmatchable.
- The scrolling capture stops by itself after 300 kept frames or 10 minutes.
- `output` asks Hyprland (`hyprctl`) or Sway (`swaymsg`) for the focused
  monitor. On other compositors you click the monitor to grab.

## Development

```
make test
```

Runs the CLI against stubbed tools (nothing is captured), the stitcher on
synthetic frames, and the overlay's placement logic under Node.

## License

MIT
