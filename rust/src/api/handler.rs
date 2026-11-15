//! The bridge's task handler, defined here instead of generated so the
//! browser build never evaluates a string as code: the generated web
//! handler finds the core's script URL for its worker pool with `eval`,
//! which the web wallet's Content-Security-Policy forbids. Here the pool is
//! given the URL (index.html loads `pkg/null_light_core.js` from the page's
//! own origin). Native builds use the generated default unchanged.

use std::sync::LazyLock;

use flutter_rust_bridge::for_generated::SimpleThreadPool;
use flutter_rust_bridge::DefaultHandler;

/// The handler every bridge call goes through.
#[cfg(not(target_family = "wasm"))]
pub static FLUTTER_RUST_BRIDGE_HANDLER: LazyLock<DefaultHandler<SimpleThreadPool>> =
    LazyLock::new(|| DefaultHandler::new_simple(SimpleThreadPool::default()));

#[cfg(target_family = "wasm")]
thread_local! {
    static THREAD_POOL: SimpleThreadPool = web::worker_pool();
}

/// The handler every bridge call goes through.
#[cfg(target_family = "wasm")]
pub static FLUTTER_RUST_BRIDGE_HANDLER: LazyLock<
    DefaultHandler<&'static std::thread::LocalKey<SimpleThreadPool>>,
> = LazyLock::new(|| DefaultHandler::new_simple(&THREAD_POOL));

#[cfg(target_family = "wasm")]
mod web {
    use flutter_rust_bridge::for_generated::SimpleThreadPool;
    use js_sys::Reflect;
    use wasm_bindgen::JsValue;

    /// Where index.html loads the core's glue script from.
    const SCRIPT: &str = "/pkg/null_light_core.js";

    /// The page's origin, read without evaluating code.
    fn origin() -> Option<String> {
        let location = Reflect::get(&js_sys::global(), &JsValue::from_str("location")).ok()?;
        Reflect::get(&location, &JsValue::from_str("origin"))
            .ok()?
            .as_string()
    }

    /// The bridge's worker pool, pointed at the core's script.
    #[allow(clippy::expect_used)] // No pool means no bridge calls at all.
    pub(super) fn worker_pool() -> SimpleThreadPool {
        let script = origin().map(|o| format!("{o}{SCRIPT}"));
        SimpleThreadPool::new(None, script, None, None).expect("start the bridge's worker pool")
    }
}
