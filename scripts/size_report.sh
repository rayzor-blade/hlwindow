#!/usr/bin/env bash
# What the native library is made of: its released (stripped) size, and
# cargo-bloat's largest crates in the same build with its symbols kept.
#
#     scripts/size_report.sh [crates]     # 20 by default
#
# Needs cargo-bloat (`cargo install cargo-bloat`). cargo-bloat measures only
# a library built as a cdylib alone, so it measures a copy of the crate.
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
crates=${1:-20}
work="$here/target/size-report"
rm -rf "$work/src"
mkdir -p "$work/src"
(cd "$here" && tar cf - --exclude ./target --exclude ./.git .) | (cd "$work/src" && tar xf -)
sed -i.orig 's/^crate-type = .*/crate-type = ["cdylib"]/' "$work/src/Cargo.toml"
cd "$work/src"
export CARGO_TARGET_DIR="$work/target"

cargo build --quiet --release --lib
for lib in "$CARGO_TARGET_DIR"/release/{libhlwindow.dylib,libhlwindow.so,hlwindow.dll}; do
  [ -f "$lib" ] && break
done
echo "released size: $(wc -c < "$lib" | tr -d ' ') bytes ($(basename "$lib"))"
echo
CARGO_PROFILE_RELEASE_STRIP=false cargo bloat --quiet --release --lib --crates -n "$crates"
