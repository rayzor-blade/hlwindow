# hlwindow

[xwindow](https://github.com/rayzor-blade/xwindow)'s window adapter for
HashLink and Ash. It provides the Haxe `window` package, loaded as
`xwindow.hdll` natively or as the side module `xwindow.wasm` in a page.

`build.rs` generates the window model and primitives from xwindow, installs
the backend for the target, and writes the Haxe API into `haxe/window`. The
Haxe sources are committed, since whoever uses them is not building the crate.

## Installing

Install the `hlwindow-<version>.zip` from a release:

    haxelib install hlwindow-0.1.0.zip

and compile with `-lib hlwindow`. The ZIP carries `xwindow.hdll` for every
desktop platform; `extraParams.hxml` copies the host's beside the generated
`.hl`. A source checkout has no hdlls, so `-lib` on one fails until you define
`hlwindow_no_hdll` and put `xwindow.hdll` where HashLink finds it yourself.

The browser side module is the separate `hlwindow-wasm-ash.zip`.

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
