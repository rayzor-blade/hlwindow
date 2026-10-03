# hlwindow

[xwindow](https://github.com/rayzor-blade/xwindow)'s window adapter for
HashLink and Ash. It provides the Haxe `window` package, loaded as
`xwindow.hdll` natively or as the side module `xwindow.wasm` in a page.

`build.rs` generates the window model and primitives from xwindow, installs
the backend for the target, and writes the Haxe API into `haxe/window`. The
Haxe sources are committed, since whoever uses them is not building the crate.

## Installing

Install `hlwindow.zip` from a [release](https://github.com/rayzor-blade/hlwindow/releases).
The rolling `nightly` is rebuilt daily when `main` has changed, and the
latest is always at
<https://github.com/rayzor-blade/hlwindow/releases/download/nightly/hlwindow.zip>:

    haxelib install hlwindow.zip

Installing a newer nightly the same way replaces the old one. A versioned
release takes its version from its tag; a nightly keeps the one in
`haxelib.json`, which changes only when xwindow's API does.

Compile with `-lib hlwindow`. The ZIP carries `xwindow.hdll` for every
desktop platform; `extraParams.hxml` copies the host's beside the generated
`.hl`. A source checkout has no hdlls, so `-lib` on one fails until you define
`hlwindow_no_hdll` and put `xwindow.hdll` where HashLink finds it yourself.

The browser side module is the separate `hlwindow-wasm-ash.zip`.

A mobile app links HashLink and its libraries statically, so iOS and Android
releases ship the static library `libhlwindow.a` rather than an hdll, one ZIP
per target:

| ZIP | Target |
|---|---|
| `hlwindow-ios-arm64.zip` | `aarch64-apple-ios` |
| `hlwindow-ios-simulator.zip` | `aarch64-apple-ios-sim` |
| `hlwindow-android-arm64.zip` | `aarch64-linux-android` |
| `hlwindow-android-arm.zip` | `armv7-linux-androideabi` |
| `hlwindow-android-x64.zip` | `x86_64-linux-android` |

Each ZIP has `include/xwindow.h`, the event-loop hook for an app in C, as
xwindow's CONTRIBUTING.md describes:

- On iOS the app's `main` calls `xwindow_run_turns`, which runs the loop and
  gives the program its turns; it never returns.
- On Android the archive's `android_main` keeps the activity's app and calls
  `xwindow_main`, which the app defines as its program. That program calls
  `xwindow_attach_pump` or `xwindow_run_turns`, or simply opens a window,
  which pumps.

The Android archives are built with winit's NativeActivity and the
`android-main` feature. A Rust host depends on hlwindow as a crate, defines
its own `android_main`, and calls `hlwindow::attach`; a host on a
GameActivity builds with `--no-default-features --features
android-game-activity`.

## Building

    cargo build --release        # target/release/libhlwindow.{dylib,so} / hlwindow.dll
    scripts/build_wasm.sh        # target/wasm/xwindow.wasm, xwindow.mjs, xwindow_wire.mjs

The native library is renamed to `xwindow.hdll` for HashLink. The wasm build
needs a nightly toolchain with `rust-src`.

## Surfaces

`Window.platform()` and `Window.raw(0..3)` are the arguments
[hlwgpu](https://github.com/rayzor-blade/hlwgpu)'s `GpuInstance.surface()`
takes. Neither library depends on the other.

## License

MIT
