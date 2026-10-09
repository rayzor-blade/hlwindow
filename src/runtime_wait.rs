//! Join Ash's cooperative scheduler to the native event loop. Stock HashLink
//! uses OS threads; older Ash keeps its bounded wait until it has these hooks.

use std::sync::OnceLock;

type Prepare = unsafe extern "C" fn(f64, unsafe extern "C" fn()) -> f64;
type Resume = unsafe extern "C" fn();

enum Runtime {
    Ash { prepare: Prepare, resume: Resume },
    LegacyAsh,
    Threads,
}

impl Runtime {
    fn get() -> &'static Self {
        static RUNTIME: OnceLock<Runtime> = OnceLock::new();
        RUNTIME.get_or_init(|| {
            #[cfg(unix)]
            let modules = [Some(libloading::os::unix::Library::this())];
            #[cfg(windows)]
            let modules = [
                libloading::os::windows::Library::this().ok(),
                libloading::os::windows::Library::open_already_loaded("libhl.dll").ok(),
                libloading::os::windows::Library::open_already_loaded("ash_std.dll").ok(),
            ];
            let mut legacy = false;
            for module in modules.into_iter().flatten() {
                unsafe {
                    if let (Ok(prepare), Ok(resume)) = (
                        module.get::<Prepare>(b"ash_host_wait\0"),
                        module.get::<Resume>(b"ash_host_resumed\0"),
                    ) {
                        return Self::Ash {
                            prepare: *prepare,
                            resume: *resume,
                        };
                    }
                    legacy |= module.get::<Resume>(b"hlp_fiber_poll\0").is_ok();
                }
            }
            if legacy {
                Self::LegacyAsh
            } else {
                Self::Threads
            }
        })
    }
}

unsafe extern "C" fn wake() {
    unsafe {
        crate::backend::window_wake();
    }
}

pub struct Wait {
    pub timeout: f64,
    resume: Option<Resume>,
}

impl Wait {
    pub fn begin(timeout: f64) -> Self {
        match Runtime::get() {
            Runtime::Ash { prepare, resume } => Self {
                timeout: unsafe { prepare(timeout, wake) },
                resume: Some(*resume),
            },
            Runtime::LegacyAsh => Self {
                timeout: if timeout < 0.0 { 0.1 } else { timeout.min(0.1) },
                resume: None,
            },
            Runtime::Threads => Self {
                timeout,
                resume: None,
            },
        }
    }
}

impl Drop for Wait {
    fn drop(&mut self) {
        if let Some(resume) = self.resume {
            unsafe {
                resume();
            }
        }
    }
}
