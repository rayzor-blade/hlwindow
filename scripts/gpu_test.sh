#!/bin/sh
# Hand an xwindow window to xgpu and draw to it under Ash, natively and in a
# page, and check that the triangle examples/gpu/Triangle.hx draws is there.
#
#     scripts/gpu_test.sh [native|page|all]
#
# Exits 0 when every mode run presented frames without failing and its
# screenshot shows the triangle. Work files go to target/gpu-test.
#
# Needs, on macOS:
#   * Ash with page side-module loading (ash d19312b or later): `ash` on PATH,
#     or ASH=/path/to/ash.
#   * haxe 4.3, node 22 or later, cargo, and nightly with rust-src for the wasm
#     side modules (page mode).
#   * ash-future's Haxe sources: ASH_FUTURE=<dir with ash/Future.hx>, else
#     `haxelib libpath ash-future`, else haxelib/ash-future in the Ash
#     checkout ASH was built in.
#   * hlwgpu: HLWGPU=<checkout> builds that one as it is; otherwise hlwgpu is
#     cloned into target/gpu-test at the revision Cargo.toml pins hl_xidl to.
#   * native: Screen Recording permission for the terminal, for screencapture.
#     The window must stay uncovered while it draws.
#   * page: Google Chrome, or CHROME=/path/to/chrome. It runs headless.
set -e

here=$(cd "$(dirname "$0")/.." && pwd)
mode=${1:-all}
case $mode in native | page | all) ;; *) echo "usage: $0 [native|page|all]" >&2; exit 2 ;; esac
work="$here/target/gpu-test"
mkdir -p "$work"
# Fewer than this many frames in four seconds is not drawing at vsync.
min_frames=30

fail() { echo "gpu_test: $*" >&2; exit 1; }

ash=${ASH:-$(command -v ash || true)}
[ -x "$ash" ] || fail "no ash: put it on PATH or set ASH"

future=${ASH_FUTURE:-$(haxelib libpath ash-future 2>/dev/null || true)}
[ -f "$future/ash/Future.hx" ] || future="$(dirname "$ash")/../../haxelib/ash-future"
[ -f "$future/ash/Future.hx" ] || fail "no ash-future sources: set ASH_FUTURE"

if [ -n "$HLWGPU" ]; then
  hlwgpu=$HLWGPU
else
  hlwgpu="$work/hlwgpu"
  rev=$(sed -n 's/^hl_xidl = .*rev = "\([0-9a-f]*\)".*/\1/p' "$here/Cargo.toml")
  [ -n "$rev" ] || fail "no hl_xidl revision in Cargo.toml"
  [ -d "$hlwgpu/.git" ] || git clone -q https://github.com/rayzor-blade/hlwgpu.git "$hlwgpu"
  if [ "$(git -C "$hlwgpu" rev-parse HEAD)" != "$rev" ]; then
    git -C "$hlwgpu" fetch -q origin
    git -C "$hlwgpu" checkout -q "$rev"
  fi
fi
echo "hlwgpu: $hlwgpu at $(git -C "$hlwgpu" rev-parse --short HEAD 2>/dev/null || echo '?')"

# Runs a command for at most $1 seconds.
bounded() {
  limit=$1
  shift
  "$@" &
  pid=$!
  # Detached from the output, so a pipe reading it is not held open.
  ( sleep "$limit" && kill "$pid" ) < /dev/null > /dev/null 2>&1 &
  watchdog=$!
  status=0
  wait "$pid" || status=$?
  kill "$watchdog" 2>/dev/null || true
  [ $status -ne 143 ] || echo "gpu_test: stopped after ${limit}s: $*" >&2
  return $status
}

echo "== compiling examples/gpu/Triangle.hx"
haxe -cp "$here/examples/gpu" -cp "$here/haxe" -cp "$hlwgpu/haxe" -cp "$future" \
  -main Triangle -hl "$work/triangle.hl"

result=0
server=
browser=
# A page run leaves a server and a browser behind if it is interrupted.
trap 'kill $server $browser 2>/dev/null || true' EXIT INT TERM

# Each mode runs in an || list, where set -e does not apply, so its steps
# return on failure themselves.
native() {
  echo "== native"
  (cd "$here" && cargo build --release) || return 1
  (cd "$hlwgpu" && cargo build --release -p hlwgpu) || return 1
  dir="$work/native"
  rm -rf "$dir"
  mkdir -p "$dir"
  cp "$work/triangle.hl" "$dir/" || return 1
  cp "$here/target/release/libhlwindow.dylib" "$dir/xwindow.hdll" || return 1
  cp "$hlwgpu/target/release/libhlwgpu.dylib" "$dir/xgpu.hdll" || return 1
  status=0
  # --poll: see Triangle.settled.
  (cd "$dir" && bounded 60 "$ash" triangle.hl --seconds 4 --poll --capture frame.png) > "$dir/run.log" 2>&1 || status=$?
  cat "$dir/run.log"
  frames=$(sed -n 's/^presented \([0-9]*\) frame.*/\1/p' "$dir/run.log")
  if [ "$status" -ne 0 ]; then
    echo "native: FAIL: ash exited with $status"
    return 1
  fi
  if [ "${frames:-0}" -lt "$min_frames" ]; then
    echo "native: FAIL: ${frames:-no} frame(s) presented, expected at least $min_frames"
    return 1
  fi
  [ -f "$dir/frame.png" ] || { echo "native: FAIL: no screenshot (Screen Recording permission?)"; return 1; }
  node "$here/examples/gpu/triangle.mjs" "$dir/frame.png" || {
    echo "native: FAIL: the screenshot does not show the triangle (was the window covered?)"
    return 1
  }
  echo "native: PASS, $frames frame(s)"
}

page() {
  echo "== page"
  chrome=${CHROME:-"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"}
  [ -x "$chrome" ] || { echo "page: FAIL: no Chrome at $chrome; set CHROME"; return 1; }
  "$here/scripts/build_wasm.sh" "$work/xwindow-wasm" || return 1
  (cd "$hlwgpu" && scripts/build_wasm.sh "$work/xgpu-wasm") || return 1
  dir="$work/page"
  rm -rf "$dir"
  mkdir -p "$dir"
  cp "$work/xwindow-wasm/xwindow.wasm" "$work/xwindow-wasm/xwindow.mjs" "$work/xwindow-wasm/xwindow_wire.mjs" "$dir/" || return 1
  cp "$work/xgpu-wasm/xgpu.wasm" "$work/xgpu-wasm/gpu.mjs" "$work/xgpu-wasm/gpu-worker.mjs" \
    "$work/xgpu-wasm/gpu-agent.mjs" "$work/xgpu-wasm/hlwgpu.js" "$dir/" || return 1
  # Built beside the side modules, so the page loads them. The fiber transform
  # lets an await suspend while the page completes it.
  ASH_WASM_FIBERS=1 "$ash" --build "$dir/triangle.wasm" --target wasm32-wasip1-threads "$work/triangle.hl" || return 1
  cat "$dir/libraries.json"

  free_port() { node -e 'const s = require("net").createServer().listen(0, "127.0.0.1", () => { console.log(s.address().port); s.close(); })'; }
  port=$(free_port)
  debug=$(free_port)
  "$ash" serve --port "$port" "$dir" > "$work/serve.log" 2>&1 &
  server=$!
  rm -rf "$work/chrome-profile"
  "$chrome" --headless=new --no-first-run --no-default-browser-check \
    --user-data-dir="$work/chrome-profile" --remote-debugging-port="$debug" \
    --force-device-scale-factor=2 --window-size=1280,1000 about:blank > "$work/chrome.log" 2>&1 &
  browser=$!
  status=0
  bounded 150 node "$here/examples/gpu/page.mjs" "http://127.0.0.1:$port/index.html" "$debug" "$work/page-frame.png" "$min_frames" || status=$?
  kill "$browser" "$server" 2>/dev/null || true
  wait "$browser" "$server" 2>/dev/null || true
  server=
  browser=
  return $status
}

if [ "$mode" = native ] || [ "$mode" = all ]; then native || result=1; fi
if [ "$mode" = page ] || [ "$mode" = all ]; then page || result=1; fi
[ $result -eq 0 ] && echo "gpu_test: PASS ($mode)" || echo "gpu_test: FAIL ($mode)"
exit $result
