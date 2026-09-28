# Building the Web Engine (SwiftWasm)

"Export as Website" ships a static player by default. To make exported sites
**interactive** — scripts running in the browser via the same HyperTalk
interpreter the app uses — the engine is compiled to WebAssembly once per
release and bundled into the app as `Contrapt/WebEngine.zip`.

## Pieces

- `WasmPlayer/` — a separate SwiftPM package (so the app's Xcode graph never
  touches JavaScriptKit): `ContraptEngineWasm` reads `window.__STACK__`,
  builds a `StackEngine`, and installs `window.ContraptEngine`
  (async `snapshot`/`start`/`mouseUp`/`openCard`/`message`, JSON envelopes).
- `Scripts/build-web-engine.sh` — builds it with the wasm Swift SDK and zips
  the PackageToJS bundle into `Contrapt/WebEngine.zip` (auto-bundled by the
  synchronized folder).
- `WebsiteExporter` — when `WebEngine.zip` is in the app bundle, exports
  `engine/` + `boot.js` sets `window.__HAS_ENGINE__`; `player.js` upgrades
  itself when `window.ContraptEngine` exists, else stays a static preview.
- Dialogs: the page may define `window.ContraptDialogs = { answer(prompt,
  buttons), ask(prompt, initial) }` (may return promises). Without it,
  `answer` resolves to the default (last) button and `ask` uses
  `window.prompt`.

## One-time toolchain setup

Xcode's Swift **cannot** target WebAssembly; a swift.org toolchain of the
**exact same version** as the wasm Swift SDK is required (hard rule from 6.1
on). As of 2026-09: Swift 6.3 + swift-wasm-6.3-RELEASE.

```sh
# 1. swiftly (the swift.org toolchain manager)
brew install swiftly && swiftly init

# 2. The open-source 6.3 toolchain (~1 GB)
swiftly install 6.3

# 3. The matching WebAssembly Swift SDK — URL + checksum from
#    https://github.com/swiftwasm/swift/releases/tag/swift-wasm-6.3-RELEASE
swiftly run swift sdk install +6.3 \
  https://github.com/swiftwasm/swift/releases/download/swift-wasm-6.3-RELEASE/swift-wasm-6.3-RELEASE-wasm32-unknown-wasip1.artifactbundle.zip \
  --checksum 6704d137e532f1ac31eafedd80658f9ee61239f2b6291216a02da32361ea9dcb

# 4. Verify
swiftly run swift sdk list +6.3       # → 6.3-RELEASE_wasm
```

If the Swift versions here have moved on, install the matching pair and pass
`CONTRAPT_WASM_TOOLCHAIN` / `CONTRAPT_WASM_SDK` to the build script.

## Build + bundle

```sh
./Scripts/build-web-engine.sh
```

Then rebuild the app. `File ▸ Export as Website` now emits `engine/` beside
the player; open the exported `index.html` (or serve the folder) and the
"Static preview" note disappears — clicks dispatch `mouseUp`, paging sends
`openCard`, `answer`/`ask`/`wait` work.

## Notes / limits

- Payload: the .wasm is multi-MB (Foundation subset included). Acceptable for
  v1; Embedded Swift mode is the future slimming path.
- `WasmPlayer` builds natively on macOS too (`cd WasmPlayer && swift build`) —
  JavaScriptKit compiles with stubs — so the bridge is type-checked in CI/dev
  without the wasm SDK.
- The PackageToJS output path or its `index.js` export shape may shift between
  JavaScriptKit releases; `boot.js` tries `init` then the default export, and
  the build script fails loudly if the bundle isn't where expected.
