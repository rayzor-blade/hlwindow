//! A window for HashLink and Ash: xwindow's generated `window` API over
//! winit natively, built as `xwindow.hdll`. For wasm it builds the side
//! module `xwindow.wasm`, whose window is the page's canvas, served by the
//! agent the host starts through `ash_host_agent("xwindow", block)`.

#![allow(non_snake_case, improper_ctypes_definitions, clippy::all)]
#![allow(unsafe_op_in_unsafe_fn)]
#![cfg_attr(
    all(target_arch = "wasm32", target_feature = "atomics"),
    feature(stdarch_wasm_atomic_wait, thread_local)
)]

#[cfg(target_family = "wasm")]
#[global_allocator]
static ALLOCATOR: hl_abi::ProgramAllocator = hl_abi::ProgramAllocator;

// As in hlwgpu: a side module cannot import the TLS errno threaded WASI's
// std addresses, and nothing here reports through it.
#[cfg(target_family = "wasm")]
#[unsafe(no_mangle)]
#[cfg_attr(target_feature = "atomics", thread_local)]
static mut errno: i32 = 0;

mod runtime {
    pub use hl_xidl::*;

    /// hl_xidl's host hooks, and HashLink's blocking convention for the
    /// native backend's pump.
    pub mod host {
        pub use hl_xidl::host::*;

        #[cfg(not(target_family = "wasm"))]
        unsafe extern "C" {
            fn hl_blocking(yes: bool);
        }

        /// Marks this thread as outside the heap, so the collector may run
        /// without it.
        #[cfg(not(target_family = "wasm"))]
        pub fn blocking(yes: bool) {
            unsafe { hl_blocking(yes) }
        }
    }
}

#[cfg(not(target_family = "wasm"))]
mod backend {
    include!(concat!(env!("OUT_DIR"), "/xwindow_backend/native.rs"));
}

/// The host's hook, for a host that builds the event loop (on Android, with
/// its `AndroidApp`) or runs it and gives the program turns (on iOS), with
/// the winit it is built from.
#[cfg(not(target_family = "wasm"))]
pub use backend::{Drive, attach};
#[cfg(not(target_family = "wasm"))]
pub use winit;

/// For an app that links the library from C on Android: winit's activity
/// calls this, which keeps the app for the backend and starts the app's
/// program, `xwindow_main` (include/xwindow.h).
#[cfg(all(target_os = "android", feature = "android-main"))]
#[unsafe(no_mangle)]
fn android_main(app: winit::platform::android::activity::AndroidApp) {
    unsafe extern "C" {
        fn xwindow_main();
    }
    backend::android_app(app);
    unsafe { xwindow_main() }
}

#[cfg(target_family = "wasm")]
#[allow(dead_code, non_camel_case_types, unused_variables)]
mod wire {
    include!(concat!(env!("OUT_DIR"), "/window_wire.rs"));
}

#[cfg(target_family = "wasm")]
mod web {
    include!(concat!(env!("OUT_DIR"), "/xwindow_backend/web.rs"));
}

#[cfg(target_family = "wasm")]
mod backend {
    use super::*;
    include!(concat!(env!("OUT_DIR"), "/window_web_backend.rs"));
}

#[allow(unused_imports)]
use runtime::{Buffer, BufferMut, Enum, ErrorKind, Future, NativeEnum, Rooted, Text, host};

include!(concat!(env!("OUT_DIR"), "/window.rs"));
