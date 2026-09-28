# Building the Web Engine (SwiftWasm)

"Export as Website" ships a static player by default. To make exported sites
**interactive** — scripts running in the browser via the same HyperTalk
interpreter the app uses — the engine is compiled to WebAssembly once per
release and bundled into the app as `Contrapt/WebEngine.zip`.

**Status 2026-09-28: working end to end.** The engine was verified under node
(snapshot/start/openCard/message against a real stack) and in headless Chrome
(exported site loads the wasm, installs `window.ContraptEngine`, the player
upgrades to interactive: static-preview note cleared, parts carry script ids).

## Pieces

- `WasmPlayer/` — a separate SwiftPM package (so the app's Xcode graph never
  touches JavaScriptKit): `ContraptEngineWasm` reads `window.__STACK__`,
  builds a `StackEngine`, and installs `window.ContraptEngine`
  (async `snapshot`/`start`/`mouseUp`/`openCard`/`message`, JSON envelopes).
  It also builds natively (`cd WasmPlayer && swift build`) for type-checking.
- `Scripts/build-web-engine.sh` — builds with the wasm Swift SDK (PackageToJS
  plugin), vendors the WASI shim (npm) and rewrites its bare import so the
  site is self-contained, zips the bundle into `Contrapt/WebEngine.zip`
  (auto-bundled by the synchronized folder; gitignored — a build artifact).
- `WebsiteExporter` — when `WebEngine.zip` is in the app bundle, the export
  gains `engine/` and `boot.js` loads it before injecting `player.js` (which
  captures `window.ContraptEngine` at load). `stack-data.js` carries
  `__HAS_ENGINE__`. boot.js is deliberately a *classic* script: module
  scripts don't load from `file://` at all. Its dynamic `import()` fails
  under `file://` (local-file CORS) and is caught — so double-clicking
  `index.html` gives the static preview, and any web server (GitHub Pages,
  `python3 -m http.server`) gives the interactive engine.
- Dialogs: the page may define `window.ContraptDialogs = { answer(prompt,
  buttons), ask(prompt, initial) }` (may return promises). Without it,
  `answer` resolves to the default (last) button and `ask` uses
  `window.prompt`.

## One-time toolchain setup (done on this machine 2026-09-28)

Xcode's Swift **cannot** target WebAssembly; a swift.org toolchain of the
**exact same version** as the wasm Swift SDK is required (hard rule from
Swift 6.1 on). Installed here: Swift **6.3.3** + `swift-6.3.3-RELEASE_wasm`.

```sh
# 1. swiftly (the swift.org toolchain manager) + the open toolchain (~1 GB)
brew install swiftly && swiftly init
swiftly install 6.3.3

# 2. The version-matched WebAssembly Swift SDK (swift.org hosts these; ~70 MB)
curl -LO https://download.swift.org/swift-6.3.3-release/wasm-sdk/swift-6.3.3-RELEASE/swift-6.3.3-RELEASE_wasm.artifactbundle.tar.gz
swiftly run swift sdk install +6.3.3 swift-6.3.3-RELEASE_wasm.artifactbundle.tar.gz
# (sha256 of the 6.3.3 bundle, for the record:
#  cabfa08b73bb8ac783927ecd15fa386e99d0c139c5f232445067bcf58379cae7)

# 3. Verify — should list swift-6.3.3-RELEASE_wasm (+ -embedded)
swiftly run swift sdk list +6.3.3

# 4. node (the build script uses npm to vendor the WASI shim)
brew install node
```

When Swift moves on, install the matching pair and pass
`CONTRAPT_WASM_TOOLCHAIN` / `CONTRAPT_WASM_SDK` to the build script.
JavaScriptKit 0.59+ requires Swift 6.3+.

## Build + bundle

```sh
./Scripts/build-web-engine.sh    # → Contrapt/WebEngine.zip (~20 MB)
```

Then rebuild the app. `File ▸ Export as Website` now emits `engine/` beside
the player. Serve the exported folder over http and the "Static preview"
note disappears — clicks dispatch `mouseUp`, paging sends `openCard`,
`answer`/`ask`/`wait` work.

Quick smoke test of a fresh engine build without the app (node):
set `globalThis.__STACK__` to a stack.json object, `defaultNodeSetup()` +
`instantiate()` from the bundle, then call `globalThis.ContraptEngine`.

## Notes / limits

- The `.wasm` is ~63 MB raw / ~20 MB zipped (Foundation subset + debug
  metadata). Slimming paths, untried: `wasm-opt -Oz --strip-debug`
  (binaryen), and eventually Embedded Swift (`swift-6.3.3-RELEASE_wasm-embedded`
  is already installed) — but Embedded means no full Foundation, so the
  engine's JSONDecoder use would need rework. Ship the fat one first.
- The PackageToJS output path (`.build/plugins/PackageToJS/outputs/Package`)
  and its `index.js` `init` export are version-specific to JavaScriptKit
  0.59; the build script fails loudly if the bundle moves.
- `WebEngine.zip` is gitignored. Beta checklist: run
  `./Scripts/build-web-engine.sh` before archiving if exports should be
  interactive in the shipped build.
