//
//  WebsiteExporter.swift
//  Contrapt
//
//  Exports a stack as a self-contained static website folder — the packaging
//  half of the "Export as Website" feature (see the export-as-website design).
//  It writes the already-web-ready `stack.json`, the referenced `assets/`, and
//  a small static player (`index.html` + `player.js`) so the stack can be
//  browsed in any browser with no server.
//
//  This layer deliberately touches neither the HyperTalk interpreter nor the
//  host protocol: the player is a *static preview* (you can page through cards
//  and see fields/buttons/labels/images/paint), and scripting is a later phase
//  that drops the SwiftWasm-compiled interpreter in beside these files. The
//  design decision (SwiftWasm, not a JS reimplementation) is why this split is
//  safe — the language runtime arrives without touching this packaging.
//

import Foundation

enum WebsiteExporter {
    struct ExportError: LocalizedError { let message: String; var errorDescription: String? { message } }

    /// The site's files as a path→bytes map: `index.html`, `player.js`,
    /// `stack.json`, `stack-data.js`, and `assets/<name>` for each referenced
    /// asset. Shared by the macOS folder export and the iOS zip. `actualSize`
    /// bakes the player's display mode (card at true size vs. scaled to fill).
    static func siteEntries(stack: Stack, assets: [String: Data], actualSize: Bool) throws -> [String: Data] {
        var entries: [String: Data] = [:]
        let json = try stack.fileData()
        entries["stack.json"] = json
        // The compiled Wasm engine, when the app bundles it (WebEngine.zip,
        // built by Scripts/build-web-engine.sh), makes the export interactive:
        // boot.js loads it, it installs window.ContraptEngine, and player.js
        // upgrades itself. Without it the site is the static preview.
        let engineFiles = bundledEngineEntries()
        for (path, data) in engineFiles { entries["engine/\(path)"] = data }
        // Also emit the data as a JS global. Opening index.html from a file://
        // URL blocks fetch() of a sibling file (local-file CORS), so the player
        // reads window.__STACK__ from a <script> (which loads fine locally) and
        // only falls back to fetch when the site is served over http.
        let dataJS = "window.__STACK__ = " + (String(data: json, encoding: .utf8) ?? "null") + ";\n"
            + "window.__ACTUAL_SIZE__ = " + (actualSize ? "true" : "false") + ";\n"
            + "window.__HAS_ENGINE__ = " + (engineFiles.isEmpty ? "false" : "true") + ";\n"
        entries["stack-data.js"] = Data(dataJS.utf8)
        entries["index.html"] = Data(indexHTML.utf8)
        entries["player.js"] = Data(playerJS.utf8)
        entries["boot.js"] = Data(bootJS.utf8)
        for name in stack.referencedAssetNames() {
            guard let data = assets[name] else { continue }
            entries["assets/\(name)"] = data
        }
        return entries
    }

    /// The compiled Wasm engine's files (the PackageToJS bundle), read from
    /// the app resource `WebEngine.zip` — present only after running
    /// Scripts/build-web-engine.sh. Empty means export the static preview.
    private static func bundledEngineEntries() -> [String: Data] {
        guard let url = Bundle.main.url(forResource: "WebEngine", withExtension: "zip"),
              let data = try? Data(contentsOf: url),
              let files = try? ZipArchive.extract(data) else { return [:] }
        // Drop the zip's directory placeholders — a "name/" entry is not a
        // file, and writing one as a file would collide with the directory.
        return files.filter { !$0.key.hasSuffix("/") }
    }

    /// A filesystem-safe base name for the exported site (no path separators).
    static func folderName(for stack: Stack) -> String {
        sanitizedFolderName(stack.name.isEmpty ? "Stack" : stack.name) + " Website"
    }

    /// Writes a static-website folder for `stack` into `parentDirectory`
    /// (macOS), returning the created site folder.
    @discardableResult
    static func export(stack: Stack, assets: [String: Data], into parentDirectory: URL, actualSize: Bool = false) throws -> URL {
        let fm = FileManager.default
        let site = parentDirectory.appendingPathComponent(folderName(for: stack), isDirectory: true)
        // Fresh folder each export so stale cards/assets don't linger.
        if fm.fileExists(atPath: site.path) { try fm.removeItem(at: site) }
        try fm.createDirectory(at: site, withIntermediateDirectories: true)
        for (path, data) in try siteEntries(stack: stack, assets: assets, actualSize: actualSize) {
            let dest = site.appendingPathComponent(path)
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: dest)
        }
        return site
    }

    /// The site packaged as a `.zip` (store-only), for platforms without a
    /// folder picker (iOS) — the user unzips and opens `index.html`.
    static func zipData(stack: Stack, assets: [String: Data], actualSize: Bool = false) throws -> Data {
        ZipArchive.archive(try siteEntries(stack: stack, assets: assets, actualSize: actualSize))
    }

    /// A filesystem-safe folder name (drop path separators and colons).
    private static func sanitizedFolderName(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:")
        let cleaned = name.components(separatedBy: bad).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Stack" : cleaned
    }
}

// MARK: - Static player template

extension WebsiteExporter {
    static let indexHTML = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Contrapt Stack</title>
    <style>
      :root { color-scheme: light; }
      html, body { margin: 0; height: 100%; background: #6b6b6b;
        font-family: system-ui, -apple-system, Helvetica, Arial, sans-serif; }
      #stage { position: absolute; inset: 0 0 64px 0; display: flex;
        align-items: center; justify-content: center; overflow: auto; }
      #card { position: relative; background: #fff; transform-origin: center center;
        box-shadow: 0 2px 16px rgba(0,0,0,.4); overflow: hidden; }
      .paint { position: absolute; left: 0; top: 0; width: 100%; height: 100%;
        image-rendering: pixelated; pointer-events: none; }
      .part { position: absolute; box-sizing: border-box; overflow: hidden;
        color: #000; line-height: 1.15; }
      .field { white-space: pre-wrap; }
      .field.opaque, .field.rectangle, .field.shadow { background: #fff; }
      .field.rectangle { border: 1px solid #000; }
      .field.shadow { border: 1px solid #000; box-shadow: 3px 3px 0 rgba(0,0,0,.5); }
      .button { display: flex; align-items: center; justify-content: center;
        gap: 4px; text-align: center; }
      .button.rectangle, .button.shadow { border: 1px solid #000; }
      .button.roundRect { border: 1px solid #000; border-radius: 8px; }
      .button.opaque { background: #fff; }
      .button.shadow { box-shadow: 3px 3px 0 rgba(0,0,0,.5); }
      .button.hilite { background: #000; color: #fff; }
      .button .icon { image-rendering: pixelated; }
      .label { display: flex; align-items: center; }
      #bar { position: absolute; left: 0; right: 0; bottom: 0; height: 64px;
        display: flex; align-items: center; gap: 12px; padding: 0 16px;
        background: #eee; border-top: 1px solid #ccc; }
      #bar button { font-size: 15px; padding: 6px 14px; }
      #cardLabel { font-variant-numeric: tabular-nums; }
      #note { margin-left: auto; color: #888; font-size: 12px; }
      .field[contenteditable] { cursor: text; }
      .field[contenteditable]:focus { outline: 2px solid #4a90d9; outline-offset: -1px; }
      .dlg-overlay { position: fixed; inset: 0; background: rgba(0,0,0,.25);
        display: flex; align-items: center; justify-content: center; z-index: 10; }
      .dlg { background: #fff; border: 1px solid #000; border-radius: 10px;
        box-shadow: 0 12px 40px rgba(0,0,0,.4); padding: 20px 22px;
        min-width: 280px; max-width: 440px;
        font-family: system-ui, -apple-system, Helvetica, Arial, sans-serif; }
      .dlg p { margin: 0 0 14px; font-size: 15px; white-space: pre-wrap; }
      .dlg input { width: 100%; box-sizing: border-box; font-size: 15px;
        padding: 6px 8px; margin-bottom: 14px; border: 1px solid #999;
        border-radius: 6px; }
      .dlg-buttons { display: flex; justify-content: flex-end; gap: 8px; }
      .dlg-buttons button { font-size: 14px; padding: 6px 16px;
        border: 1px solid #000; border-radius: 8px; background: #fff; cursor: pointer; }
      .dlg-buttons button.default { background: #000; color: #fff; }
    </style>
    </head>
    <body>
      <div id="stage"><div id="card"></div></div>
      <div id="bar">
        <button id="prev">‹ Prev</button>
        <button id="next">Next ›</button>
        <span id="cardLabel"></span>
        <span id="note">Static preview — scripts don't run yet</span>
      </div>
      <script src="stack-data.js"></script>
      <script src="boot.js"></script>
    </body>
    </html>
    """

    /// Starts the static player immediately, and — when the export includes
    /// the Wasm engine — downloads and starts it in parallel, reporting
    /// progress to the player (the engine is tens of MB; the card must not
    /// wait for it). The player upgrades in place via __contraptEngineArrived.
    ///
    /// Deliberately a *classic* script (not type="module"): module scripts
    /// don't load from file:// at all, which would kill even the static
    /// preview. The dynamic import() below fails under file:// (local-file
    /// CORS) and is caught — engine when served over http, static otherwise.
    static let bootJS = """
    (() => {
      const s = document.createElement('script');
      s.src = 'player.js';
      document.body.appendChild(s);
      if (!window.__HAS_ENGINE__) return;

      (async () => {
        try {
          // The PackageToJS bundle: its index.js instantiates the wasm module,
          // whose main() installs window.ContraptEngine synchronously.
          const engineModule = await import('./engine/index.js');
          const init = engineModule.init ?? engineModule.default;
          // Fetch and compile the wasm ourselves instead of letting the loader
          // stream-compile the fetch: streaming requires the server to declare
          // Content-Type: application/wasm, which plenty of shared hosts don't
          // do for .wasm files. Compiling from bytes works everywhere — and
          // reading the stream by hand gives the player download progress.
          const response = await fetch('./engine/ContraptEngineWasm.wasm');
          if (!response.ok) throw new Error('engine wasm: HTTP ' + response.status);
          // Note: with Content-Encoding, content-length is the encoded size
          // while the reader yields decoded bytes — progress is clamped.
          const total = Number(response.headers.get('content-length')) || 0;
          let bytes;
          if (response.body && total > 0) {
            const reader = response.body.getReader();
            const chunks = [];
            let received = 0;
            for (;;) {
              const { done, value } = await reader.read();
              if (done) break;
              chunks.push(value);
              received += value.length;
              window.__contraptEngineProgress?.(Math.min(1, received / total));
            }
            bytes = new Uint8Array(received);
            let offset = 0;
            for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
          } else {
            bytes = new Uint8Array(await response.arrayBuffer());
          }
          window.__contraptEngineProgress?.(1); // downloading done; compiling
          const module = await WebAssembly.compile(bytes);
          await init({ module });
          window.__contraptEngineArrived?.();
        } catch (e) {
          console.warn('Contrapt engine failed to load; static preview only.', e);
          window.__contraptEngineFailed?.();
        }
      })();
    })();
    """

    static let playerJS = """
    (async function () {
      const stack = window.__STACK__ || await (await fetch('stack.json')).json();
      const bgById = {};
      (stack.backgrounds || []).forEach(b => { bgById[b.id] = b; });
      const W = stack.cardSize.width, H = stack.cardSize.height;
      const root = document.getElementById('card');
      const label = document.getElementById('cardLabel');
      const note = document.getElementById('note');
      let idx = 0;
      // scriptID -> element for the current card, rebuilt by render(); the
      // engine's CardState is overlaid onto these after each event.
      let partEls = {};

      function fontFamily(d) {
        if (d === 'serif') return 'Georgia, "Times New Roman", serif';
        if (d === 'monospaced') return 'ui-monospace, Menlo, monospace';
        if (d === 'rounded') return '"SF Pro Rounded", system-ui, sans-serif';
        return 'system-ui, -apple-system, Helvetica, Arial, sans-serif';
      }
      function styleText(el, fmt) {
        if (!fmt) return;
        el.style.fontFamily = fontFamily(fmt.fontDesign);
        el.style.fontSize = (fmt.size || 17) + 'px';
        el.style.fontWeight = fmt.isBold ? 'bold' : 'normal';
        el.style.fontStyle = fmt.isItalic ? 'italic' : 'normal';
        if (fmt.isUnderline) el.style.textDecoration = 'underline';
        el.style.justifyContent = el.style.textAlign =
          fmt.align === 'center' ? 'center' : fmt.align === 'right' ? 'right' : 'left';
      }
      function paint(asset) {
        if (!asset) return null;
        const im = document.createElement('img');
        im.className = 'paint'; im.src = 'assets/' + asset;
        return im;
      }
      function renderPart(p) {
        const d = document.createElement('div');
        d.className = 'part';
        if (p.scriptID != null) { d.dataset.scriptId = p.scriptID; partEls[p.scriptID] = d; }
        d.style.left = p.frame.x + 'px'; d.style.top = p.frame.y + 'px';
        d.style.width = p.frame.width + 'px'; d.style.height = p.frame.height + 'px';
        if (p.visible === false) { d.style.display = 'none'; return d; }
        if (p.type === 'field') {
          const f = p.field || {};
          d.className += ' field ' + (f.style || 'rectangle');
          styleText(d, f.format);
          d.textContent = f.text || '';
          // Unlocked plain fields become editable once the engine is live.
          if (f.kind !== 'rich' && !f.lockText) d.dataset.editable = '1';
        } else if (p.type === 'button') {
          const b = p.button || {};
          d.className += ' button ' + (b.style || 'roundRect') + (b.hilite ? ' hilite' : '');
          styleText(d, b.format);
          if (b.iconAsset) {
            const im = document.createElement('img');
            im.className = 'icon'; im.src = 'assets/' + b.iconAsset;
            d.appendChild(im);
          }
          if (b.showName !== false && b.title) {
            const t = document.createElement('span'); t.textContent = b.title;
            d.appendChild(t);
          }
        } else if (p.type === 'label') {
          d.className += ' label'; d.textContent = (p.label && p.label.text) || '';
        } else if (p.type === 'image') {
          const im = document.createElement('img');
          im.style.width = '100%'; im.style.height = '100%';
          im.style.imageRendering = 'pixelated';
          im.src = 'assets/' + (p.image && p.image.assetName);
          d.appendChild(im);
        }
        return d;
      }
      function fit() {
        const s = window.__ACTUAL_SIZE__
          ? 1
          : Math.min((window.innerWidth - 40) / W, (window.innerHeight - 104) / H, 2);
        root.style.transform = 'scale(' + s + ')';
      }
      function render() {
        const card = stack.cards[idx];
        const bg = bgById[card.backgroundID];
        root.innerHTML = '';
        partEls = {};
        root.style.width = W + 'px'; root.style.height = H + 'px';
        if (bg) {
          const bp = paint(bg.paintImageAsset); if (bp) root.appendChild(bp);
          (bg.parts || []).forEach(p => root.appendChild(renderPart(p)));
        }
        const cp = paint(card.paintImageAsset); if (cp) root.appendChild(cp);
        (card.parts || []).forEach(p => root.appendChild(renderPart(p)));
        label.textContent = 'Card ' + (idx + 1) + ' of ' + stack.cards.length +
          (card.name ? ' — ' + card.name : '');
        fit();
        if (engineActive) enableFieldEditing();
      }

      // --- Editable fields ---------------------------------------------------
      // With the engine live, unlocked plain fields edit in place; every input
      // pushes the text into the engine so scripts read what the visitor typed.
      function enableFieldEditing() {
        Object.values(partEls).forEach(el => {
          if (el.dataset.editable !== '1' || el.dataset.editing === '1') return;
          el.dataset.editing = '1';
          try { el.contentEditable = 'plaintext-only'; }
          catch (e) { el.contentEditable = 'true'; }
          el.addEventListener('input', () => {
            engine.setField(Number(el.dataset.scriptId), el.textContent);
          });
        });
      }
      // --- Interactive layer -------------------------------------------------
      // A Wasm runtime, when bundled, installs `window.ContraptEngine`: async
      // methods returning the JSON envelopes HyperTalkEngine emits
      //   start()            -> { effects, state }
      //   mouseUp(scriptID)  -> { effects, state }   (or { error })
      //   openCard(index)    -> { effects, state }
      // The engine loads in parallel with this player (boot.js): the static
      // card renders immediately, the status line tracks the engine download,
      // and boot.js calls __contraptEngineArrived to upgrade in place. Absent
      // an engine (a plain static export), the player just pages through cards
      // and scripts don't run.
      let engine = window.ContraptEngine;
      let engineActive = false;

      function beep() {
        try {
          const ac = new (window.AudioContext || window.webkitAudioContext)();
          const o = ac.createOscillator();
          o.frequency.value = 800; o.connect(ac.destination);
          o.start(); o.stop(ac.currentTime + 0.1);
        } catch (e) {}
      }

      // Overlay the script-visible bits (text, hilite, visibility) from the
      // engine's CardState onto the statically-rendered card.
      function applyState(state) {
        if (!state) return;
        (state.backgroundParts || []).concat(state.cardParts || []).forEach(rp => {
          const el = partEls[rp.scriptID];
          if (!el) return;
          el.style.display = rp.visible === false ? 'none' : '';
          if (rp.kind === 'field' || rp.kind === 'label') {
            // Never clobber the field the visitor is typing in.
            if (el === document.activeElement) return;
            if (el.textContent !== (rp.text || '')) el.textContent = rp.text || '';
          } else if (rp.kind === 'button') {
            el.classList.toggle('hilite', !!rp.hilite);
            const span = el.querySelector('span');
            if (span) span.textContent = rp.text || '';
          }
        });
      }

      function applyEffects(effects) {
        (effects || []).forEach(e => {
          if (e.type === 'message') note.textContent = e.text;
          else if (e.type === 'beep') beep();
          // 'navigate' is reflected by the returned state's cardIndex below.
        });
      }

      async function handle(pending) {
        let res;
        try { res = JSON.parse(await pending); } catch (e) { note.textContent = 'Engine error.'; return; }
        if (res.error) { note.textContent = 'Error: ' + res.error; return; }
        if (res.state && res.state.cardIndex !== idx) { idx = res.state.cardIndex; render(); }
        applyState(res.state);
        applyEffects(res.effects);
        if (res.result != null) note.textContent = res.result;
      }

      function go(n) {
        const wrapped = (n + stack.cards.length) % stack.cards.length;
        if (engine) { handle(engine.openCard(wrapped)); } else { idx = wrapped; render(); }
      }
      document.getElementById('prev').onclick = () => go(idx - 1);
      document.getElementById('next').onclick = () => go(idx + 1);
      window.addEventListener('resize', fit);
      document.title = stack.name || 'Contrapt Stack';
      render();

      function activateEngine() {
        engine = window.ContraptEngine;
        if (!engine || engineActive) return;
        engineActive = true;
        note.textContent = '';
        enableFieldEditing();
        // A click on any part sends mouseUp along its message path.
        root.addEventListener('click', ev => {
          const partEl = ev.target.closest('.part');
          if (!partEl || partEl.dataset.scriptId == null) return;
          handle(engine.mouseUp(Number(partEl.dataset.scriptId)));
        });
        handle(engine.start());
      }
      // --- Dialogs -----------------------------------------------------------
      // `answer` and `ask` suspend the script until the visitor responds; the
      // engine calls these (returning promises) instead of native prompts.
      function showDialog(prompt, build) {
        return new Promise(resolve => {
          const overlay = document.createElement('div');
          overlay.className = 'dlg-overlay';
          const box = document.createElement('div');
          box.className = 'dlg';
          const text = document.createElement('p');
          text.textContent = prompt;
          box.appendChild(text);
          const done = value => { overlay.remove(); resolve(value); };
          build(box, done);
          overlay.appendChild(box);
          document.body.appendChild(overlay);
        });
      }
      window.ContraptDialogs = {
        answer(prompt, buttons) {
          return showDialog(prompt, (box, done) => {
            const row = document.createElement('div');
            row.className = 'dlg-buttons';
            (buttons || ['OK']).forEach((title, i, all) => {
              const b = document.createElement('button');
              b.textContent = title;
              if (i === all.length - 1) b.className = 'default';   // HyperCard's default is the last
              b.onclick = () => done(title);
              row.appendChild(b);
            });
            box.appendChild(row);
            box.addEventListener('keydown', e => {
              if (e.key === 'Enter') { e.preventDefault(); done((buttons || ['OK']).at(-1)); }
            });
            setTimeout(() => row.lastChild && row.lastChild.focus(), 0);
          });
        },
        ask(prompt, initial) {
          return showDialog(prompt, (box, done) => {
            const input = document.createElement('input');
            input.type = 'text';
            input.value = initial || '';
            box.appendChild(input);
            const row = document.createElement('div');
            row.className = 'dlg-buttons';
            const cancel = document.createElement('button');
            cancel.textContent = 'Cancel';
            cancel.onclick = () => done(null);
            const ok = document.createElement('button');
            ok.textContent = 'OK';
            ok.className = 'default';
            ok.onclick = () => done(input.value);
            row.appendChild(cancel); row.appendChild(ok);
            box.appendChild(row);
            box.addEventListener('keydown', e => {
              if (e.key === 'Enter') { e.preventDefault(); done(input.value); }
              if (e.key === 'Escape') { e.preventDefault(); done(null); }
            });
            setTimeout(() => { input.focus(); input.select(); }, 0);
          });
        },
      };

      // boot.js drives these while the engine downloads and starts.
      window.__contraptEngineProgress = fraction => {
        if (engineActive) return;
        note.textContent = fraction >= 1
          ? 'Starting the script engine…'
          : 'Loading the script engine… ' + Math.min(99, Math.round(fraction * 100)) + '%';
      };
      window.__contraptEngineArrived = activateEngine;
      window.__contraptEngineFailed = () => {
        if (!engineActive) note.textContent = "Static preview — scripts don't run";
      };
      if (engine) {
        activateEngine();
      } else if (window.__HAS_ENGINE__) {
        note.textContent = 'Loading the script engine…';
      }
    })();
    """
}
