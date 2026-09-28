#!/bin/zsh
#
# Builds the HyperTalk engine to WebAssembly and bundles it into the app's
# resources as Contrapt/WebEngine.zip (the synchronized folder auto-bundles
# it). With that resource present, File ▸ Export as Website emits the engine
# beside the player and exported sites run their scripts in the browser.
#
# One-time setup (swiftly + Swift 6.3 toolchain + wasm Swift SDK):
# see EXPORT-WASM.md at the repo root.
#
# Override the toolchain/SDK pair via environment if versions move on:
#   CONTRAPT_WASM_TOOLCHAIN=6.3 CONTRAPT_WASM_SDK=6.3-RELEASE_wasm ./Scripts/build-web-engine.sh

set -euo pipefail
cd "$(dirname "$0")/.."

TOOLCHAIN="${CONTRAPT_WASM_TOOLCHAIN:-6.3}"
SDK="${CONTRAPT_WASM_SDK:-6.3-RELEASE_wasm}"

echo "→ Building ContraptEngineWasm with Swift $TOOLCHAIN / SDK $SDK …"
cd WasmPlayer
swiftly run swift package "+$TOOLCHAIN" --swift-sdk "$SDK" -c release js

# PackageToJS writes the browser-ready bundle (index.js + .wasm + runtime).
BUNDLE=".build/plugins/PackageToJS/outputs/Package"
if [[ ! -d "$BUNDLE" ]]; then
  echo "✗ Expected PackageToJS output at WasmPlayer/$BUNDLE — check the plugin's output path." >&2
  exit 1
fi

echo "→ Zipping bundle into Contrapt/WebEngine.zip …"
rm -f ../Contrapt/WebEngine.zip
(cd "$BUNDLE" && zip -q -r -X ../../../../../Contrapt/WebEngine.zip .)

echo "✓ Done. Rebuild the app; exports now include the interactive engine."
echo "  Engine size: $(du -h ../Contrapt/WebEngine.zip | cut -f1)"
