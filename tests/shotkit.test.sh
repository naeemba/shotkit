#!/usr/bin/env bash
# Self-check for shotkit, with stubs for grim, slurp, hyprctl, notify-send, satty,
# wl-copy, xdg-open, gio, sleep, qs and the stitcher, so nothing is captured: the
# toast's Edit, Copy, Folder and Delete each act on the saved file, Edit offers
# the toast again only when Satty changed the file, and a scrolling capture
# grabs nothing before Start, ends with no file on Cancel or a Start that never
# comes, stops on Stop, at the frame cap or after 10 minutes but not on a pause,
# drops frames that barely changed, and puts the stitcher's note in the toast.
# Also: the save directory and its config file, and the focused output lookup.
#   tests/shotkit.test.sh
# The checks read "cond && cond || fail", and fail exits; the stubs are written
# with single-quoted $ on purpose.
# shellcheck disable=SC2015,SC2016,SC2012
set -uo pipefail
directory=$(cd "$(dirname "$0")/.." && pwd)
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
export HOME=$temporary/home XDG_RUNTIME_DIR=$temporary/run XDG_CACHE_HOME=$temporary/cache XDG_CONFIG_HOME=$temporary/config
unset SHOTKIT_DIR SHOTKIT_SLURP_ARGS SHOTKIT_SCROLL_KEY XDG_PICTURES_DIR HYPRLAND_INSTANCE_SIGNATURE SWAYSOCK
export PATH=$temporary/bin:$PATH CALLS=$temporary/calls ACTIONS=$temporary/actions
mkdir -p "$HOME" "$XDG_RUNTIME_DIR" "$temporary/bin" "$temporary/copy/overlay"
# A copy beside a stub stitcher: a shotkit with an overlay directory next to it
# runs the scroll-stitch.py there too.
cp "$directory/shotkit" "$temporary/copy/"
script=$temporary/copy/shotkit
state=$XDG_RUNTIME_DIR/shotkit-scroll
pictures=$HOME/Pictures/Screenshots

# notify-send logs its title and, for the toast with buttons, answers the next
# line of $ACTIONS (nothing once they run out, as a toast that timed out).
cat > "$temporary/bin/notify-send" <<'STUB'
#!/usr/bin/env bash
summary= buttons=
while [ $# -gt 0 ]; do
  case "$1" in
    -a|-i|-t) shift;;
    --action=*) buttons=1;;
    *) summary=${summary:-$1};;
  esac
  shift
done
echo "notify $summary" >> "$CALLS"
if [ -n "$buttons" ] && [ -s "$ACTIONS" ]; then
  head -n 1 "$ACTIONS"; sed -i 1d "$ACTIONS"
fi
exit 0
STUB
# satty changes the file only when SATTY_EDIT is set.
cat > "$temporary/bin/satty" <<'STUB'
#!/usr/bin/env bash
echo "satty $2" >> "$CALLS"
[ -z "${SATTY_EDIT:-}" ] || echo edited >> "$2"
STUB
# grim writes 1000-byte frames: a different one per call for the first
# $CHANGES calls, then the same frame with one byte blinking. It touches the
# stop file at call $STOP_AT, as a second press would.
cat > "$temporary/bin/grim" <<'STUB'
#!/usr/bin/env bash
counter=$XDG_RUNTIME_DIR/grims; calls=$(( $(cat "$counter" 2>/dev/null || echo 0) + 1 ))
echo "$calls" > "$counter"
[ "$calls" = "${STOP_AT:-}" ] && touch "$XDG_RUNTIME_DIR/shotkit-scroll/stop"
[ "$1" = -t ] || echo "grim $*" >> "$CALLS"
if [ "$calls" -le "${CHANGES:-1}" ]; then
  yes "$calls" | head -c 1000 > "${@: -1}"
else
  { printf '%s' $((calls % 2)); head -c 999 /dev/zero; } > "${@: -1}"
fi
STUB
cat > "$temporary/copy/scroll-stitch.py" <<'STUB'
import os, sys
open(sys.argv[1], "wb").write(b"png")
open(os.environ["CALLS"], "a").write(f"stitch {len(sys.argv) - 2}\n")
sys.stderr.write(os.environ.get("NOTE", ""))
STUB
cat > "$temporary/bin/slurp" <<'STUB'
#!/usr/bin/env bash
echo "slurp $*" | sed 's/ $//' >> "$CALLS"; echo "0,0 10x10"
STUB
# qs, started as the overlay (qs -p DIR), says it is up and answers the way a
# click would: Start, Cancel when QS_ANSWER=cancel, nothing when
# QS_ANSWER=nothing. With QS_DOWN set it fails to start, and the "start" stands
# for a second press of the shortcut. Its IPC calls are logged.
cat > "$temporary/bin/qs" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = ipc ]; then echo "qs ${*:5:2}" >> "$CALLS"; exit 0; fi
echo "qs launch $2" >> "$CALLS"
[ -n "${QS_DOWN:-}" ] || touch "$SHOTKIT_STATE/ready"
[ "${QS_ANSWER:-}" = nothing ] || touch "$SHOTKIT_STATE/${QS_ANSWER:-start}"
[ -z "${QS_DOWN:-}" ]
STUB
# hyprctl reports DP-2 as the focused monitor.
cat > "$temporary/bin/hyprctl" <<'STUB'
#!/usr/bin/env bash
echo '[{"name":"eDP-1","focused":false},{"name":"DP-2","focused":true}]'
STUB
for command in wl-copy xdg-open gio; do
  printf '#!/usr/bin/env bash\necho "%s $*" >> "$CALLS"\n' "$command" > "$temporary/bin/$command"
done
printf '#!/usr/bin/env bash\n' > "$temporary/bin/sleep"
chmod +x "$temporary/bin/"*

fail() { echo "FAIL: $1"; echo "got:"; cat "$CALLS"; exit 1; }
# Run the script with the given toast answers and wait for its background toast
# too: it keeps fd 9 open, so the command substitution waits for it.
run() {
  rm -f "$CALLS" "$XDG_RUNTIME_DIR/grims"; printf '%s\n' "${@:2}" | sed '/^$/d' > "$ACTIONS"
  : "$("$script" "$1" 9>&1)"
  shot=$(ls "${SHOTKIT_DIR:-$pictures}"/*.png 2>/dev/null | tail -n 1)
}
has() { grep -qxF "$1" "$CALLS" 2>/dev/null; }
count() { grep -cxF "$1" "$CALLS"; }
picked() { grep -q "^slurp" "$CALLS" 2>/dev/null; }

run region copy
[ "$(count "wl-copy --type image/png")" = 2 ] || fail "Copy did not copy again"
run region folder
has "xdg-open $pictures" || fail "Folder did not open the folder"
run region delete
has "gio trash $shot" || fail "Delete did not trash the file"
run region edit
has "satty $shot" && [ "$(count "wl-copy --type image/png")" = 1 ] && [ "$(count "notify Saved and copied")" = 1 ] \
  && ! grep -q '^notify Edited' "$CALLS" || fail "an Edit that changed nothing acted"
SATTY_EDIT=1 run region default
[ "$(count "wl-copy --type image/png")" = 2 ] && has "notify Edited and copied" || fail "an Edit did not copy and offer again"

# Scrolling: 3 different frames, then a blinking one, dropped, through a long
# pause that no longer ends the capture; Stop at grab 60 does.
CHANGES=3 STOP_AT=60 NOTE="1 frame(s) did not line up" run scroll
has "stitch 4" && [ "$(cat "$XDG_RUNTIME_DIR/grims")" = 60 ] || fail "a pause ended the capture or its frames were kept"
has "notify Saved and copied (1 frame(s) did not line up)" || fail "the stitcher's note is not in the toast"
[ "$(sed -n '2,3p' "$CALLS" | tr '\n' ,)" = "qs launch $temporary/copy/overlay,qs scrollCapture record," ] \
  || fail "the overlay was not shown, then switched to recording"
has "qs scrollCapture close" || fail "the overlay was left up"
[ ! -e "$state" ] || fail "the state dir was left behind"
CHANGES=1000 run scroll
has "stitch 300" || fail "the capture did not stop at 300 frames"

# Cancel grabs nothing and saves nothing.
before=$(ls "$pictures" | wc -l)
QS_ANSWER=cancel run scroll
[ ! -e "$XDG_RUNTIME_DIR/grims" ] && ! grep -q '^stitch' "$CALLS" && [ "$(ls "$pictures" | wc -l)" = "$before" ] \
  && has "qs scrollCapture close" && [ ! -e "$state" ] || fail "a cancelled capture grabbed, saved or left the overlay up"

# Nobody presses Start: after 5 minutes it ends like Cancel. A pause nobody
# stops ends after 10 minutes of grabs.
QS_ANSWER=nothing run scroll
[ ! -e "$XDG_RUNTIME_DIR/grims" ] && ! grep -q '^stitch' "$CALLS" || fail "a Start that never came still grabbed"
CHANGES=3 run scroll
has "stitch 4" && [ "$(cat "$XDG_RUNTIME_DIR/grims")" = 3000 ] || fail "a pause nobody stopped did not end at 3000 grabs"

# With no overlay, a notification says to press the key; the capture still runs.
QS_DOWN=1 CHANGES=2 STOP_AT=2 run scroll
has "notify Scrolling capture" && has "stitch 2" && ! has "qs scrollCapture close" || fail "the capture without an overlay did not say how to start"

# A press while a capture waits for Start starts it, the next press stops it;
# neither picks a new region. A stale pid starts anew.
mkdir -p "$state"; echo $$ > "$state/pid"
run scroll
[ -e "$state/start" ] && [ ! -e "$state/stop" ] && ! picked || fail "a press while waiting did not just start"
run scroll
[ -e "$state/stop" ] && ! picked || fail "a press while recording did not just stop"
true & wait $!; echo $! > "$state/pid"; rm "$state/start" "$state/stop"
CHANGES=2 STOP_AT=3 run scroll
picked && has "stitch 3" || fail "a stale pid file blocked a new capture"

# The output mode asks Hyprland for the focused monitor; with no compositor it
# can ask, slurp -o picks one.
HYPRLAND_INSTANCE_SIGNATURE="test" run output
has "grim -o DP-2 $shot" || fail "output did not grab the focused monitor"
run output
has "slurp -d -b #1e1e2e66 -c #b4befeff -s #00000000 -w 2 -o" && has "grim -g 0,0 10x10 $shot" || fail "output without Hyprland or Sway did not let slurp pick"

# The config file sets the directory and slurp's look; the environment sets
# them without one.
mkdir -p "$XDG_CONFIG_HOME/shotkit"
printf '%s\n' "SHOTKIT_DIR=$HOME/Desktop" "SHOTKIT_SLURP_ARGS='-d -w 3'" > "$XDG_CONFIG_HOME/shotkit/config"
run region
ls "$HOME"/Desktop/*.png >/dev/null 2>&1 && has "slurp -d -w 3" || fail "the config file was not read"
rm "$XDG_CONFIG_HOME/shotkit/config"
SHOTKIT_DIR=$temporary/elsewhere run region
[ -n "$shot" ] && [ "$(dirname "$shot")" = "$temporary/elsewhere" ] || fail "SHOTKIT_DIR was not used"
"$script" bogus 2>/dev/null; [ $? = 2 ] || fail "an unknown mode was not refused"

echo "shotkit: ok"
