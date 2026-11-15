// The wallet core's wasm-bindgen glue (pkg/null_light_core.js) declares
// `wasm_bindgen` as a script-level binding. Expose it on window here, from a
// static file, so the app needs no eval and the page can run under a strict
// Content-Security-Policy (lib/src/core/platform/init_web.dart).
window.wasm_bindgen = wasm_bindgen;
