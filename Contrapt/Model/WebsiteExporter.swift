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
#if os(macOS)
import AppKit
#else
import UIKit
#endif

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
        entries[".htaccess"] = Data(htaccess.utf8)
        entries["player.js"] = Data(playerJS.utf8)
        entries["boot.js"] = Data(bootJS.utf8)
        for name in stack.referencedAssetNames() {
            guard let data = assets[name] else { continue }
            entries["assets/\(name)"] = data
        }
        // SF-symbol button icons don't exist on the web — pre-render each
        // referenced symbol to a PNG beside the other assets, so the player
        // shows the same glyph the app does.
        for (name, data) in symbolIconAssets(for: stack) {
            entries["assets/\(name)"] = data
        }
        return entries
    }

    /// PNG renderings of every SF-symbol button icon the stack uses, keyed
    /// by the asset name the player requests (`symbol-<name>.png`). Symbols
    /// a bitmap icon already overrides are skipped — the player shows the
    /// bitmap then.
    private static func symbolIconAssets(for stack: Stack) -> [String: Data] {
        var out: [String: Data] = [:]
        let parts = stack.cards.flatMap(\.parts) + stack.backgrounds.flatMap(\.parts)
        let names = Set(parts.compactMap { part -> String? in
            guard case .button(let button) = part.kind, button.iconAsset == nil,
                  let symbol = button.iconSymbol, !symbol.isEmpty else { return nil }
            return symbol
        })
        for name in names {
            guard let data = symbolPNG(name) else { continue }
            out["symbol-\(name).png"] = data
        }
        return out
    }

    /// One SF symbol rendered as a black glyph on transparent at 2x of a
    /// 64-point box — crisp at button sizes, small on disk.
    private static func symbolPNG(_ name: String) -> Data? {
        #if os(macOS)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 64, weight: .regular)) else { return nil }
        let size = symbol.size
        guard size.width > 0, size.height > 0,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                            pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        // A symbol is a template image: drawn plainly it renders black.
        symbol.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
        #else
        let configuration = UIImage.SymbolConfiguration(pointSize: 64, weight: .regular)
        guard let symbol = UIImage(systemName: name, withConfiguration: configuration)?
            .withTintColor(.black, renderingMode: .alwaysOriginal) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(size: symbol.size, format: format).pngData { _ in
            symbol.draw(at: .zero)
        }
        #endif
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
    /// Also used by BitmapExporter for its export folder.
    static func sanitizedFolderName(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:")
        let cleaned = name.components(separatedBy: bad).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Stack" : cleaned
    }
}

// MARK: - Static player template

extension WebsiteExporter {
    /// Apache hosts (Dreamhost and kin) honor a per-folder .htaccess: type
    /// .wasm correctly and compress it on the way out — the engine transfers
    /// at ~17 MB gzipped instead of 45 MB raw. Hosts without mod_deflate
    /// simply ignore the filter and serve as before.
    static let htaccess = """
    AddType application/wasm .wasm
    <IfModule mod_deflate.c>
      AddOutputFilterByType DEFLATE application/wasm application/javascript text/javascript text/html text/css application/json
    </IfModule>
    """

    static let indexHTML = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Contrapt Stack</title>
    <style>
      /* Theme variables — classic defaults; applyTheme() overrides for
         Modern Light/Dark. Classic keeps the original black-on-white look. */
      :root { color-scheme: light;
        --surface: #fff; --ink: #000; --accent: #00f; --border: #000; --padding: #6b6b6b; }
      html, body { margin: 0; height: 100%; background: var(--padding);
        font-family: system-ui, -apple-system, Helvetica, Arial, sans-serif; }
      #stage { position: absolute; inset: 0 0 64px 0; display: flex;
        align-items: center; justify-content: center; overflow: auto; }
      #card { position: relative; background: var(--surface); transform-origin: center center;
        box-shadow: 0 2px 16px rgba(0,0,0,.4); overflow: hidden; }
      .paint { position: absolute; left: 0; top: 0; width: 100%; height: 100%;
        image-rendering: pixelated; pointer-events: none; }
      .layer { position: absolute; inset: 0; background: var(--surface); }
      .part { position: absolute; box-sizing: border-box; overflow: hidden;
        color: var(--ink); line-height: 1.15; }
      .field { white-space: pre-wrap; padding: 4px 3px 3px 3px; }
      .field.rich { padding: 12px; line-height: 1.45; overflow-y: auto; }
      .field a { color: var(--accent, #0969da); text-decoration: underline; cursor: pointer; }
      .field.opaque, .field.rectangle, .field.shadow { background: var(--surface); }
      .field.rectangle { border: 1px solid var(--border); }
      .field.shadow { border: 1px solid var(--border); box-shadow: 3px 3px 0 rgba(0,0,0,.5); }
      .button { display: flex; align-items: center; justify-content: center;
        gap: 4px; text-align: center; cursor: pointer;
        -webkit-user-select: none; user-select: none; }
      /* Checkbox/radio: a glyph box before the title; hilite fills it
         (checked) instead of inverse-video. */
      .button .toggle { width: .8em; height: .8em; border: 1.5px solid currentColor;
        flex: none; position: relative; box-sizing: border-box; }
      .button.radio .toggle { border-radius: 50%; }
      .button.checkbox.hilite, .button.radio.hilite { background: transparent; color: var(--ink); }
      /* A hilited TRANSPARENT button inverts the art beneath it (real
         HyperCard's pixel flip), not a black slab. */
      .button.transparent.hilite { background: #fff; color: #fff; mix-blend-mode: difference; }
      .button.hilite .toggle::after { content: ''; position: absolute; inset: 2px;
        background: currentColor; }
      .button.radio .toggle::after { border-radius: 50%; }
      .button.rectangle, .button.shadow { border: 1px solid var(--border); }
      .button.roundRect { border: 1px solid var(--border); border-radius: 8px; }
      .button.opaque { background: var(--surface); }
      .button.shadow { box-shadow: 3px 3px 0 rgba(0,0,0,.5); }
      .button.hilite { background: var(--ink); color: var(--surface); }
      .button.has-icon { flex-direction: column; gap: 1px; }
      .button .icon { image-rendering: pixelated; flex: 1 1 0; min-height: 0;
        max-width: 100%; object-fit: contain; }
      .button .icon-missing { width: 24px; height: 24px; border: 1px dashed #999;
        border-radius: 4px; flex: none; }
      .part.disabled { opacity: .4; pointer-events: none; }
      .field.scrolling { overflow-y: auto; border: 1px solid var(--border); background: var(--surface); }
      #menus { position: absolute; top: 0; left: 0; right: 0; height: 28px;
        display: none; align-items: center; gap: 18px; padding: 0 12px;
        background: var(--surface); border-bottom: 1px solid var(--border); color: var(--ink);
        font-size: 14px; z-index: 5; user-select: none; }
      body.has-menus #menus { display: flex; }
      body.has-menus #stage { top: 28px; }
      #menus .menu { position: relative; cursor: default; }
      #menus .menu.disabled { color: #999; pointer-events: none; }
      #menus .menu .drop { display: none; position: absolute; top: 24px; left: -8px;
        min-width: 160px; background: var(--surface); border: 1px solid var(--border);
        box-shadow: 2px 2px 0 rgba(0,0,0,.4); padding: 4px 0; }
      #menus .menu.open .drop { display: block; }
      #menus .drop .item { padding: 3px 18px; white-space: nowrap; }
      #menus .drop .item:hover { background: var(--ink); color: var(--surface); }
      #menus .drop .item.disabled { color: #999; pointer-events: none; }
      .label { display: flex; align-items: center; }
      #bar { position: absolute; left: 0; right: 0; bottom: 0; height: 64px;
        display: flex; align-items: center; gap: 12px; padding: 0 16px;
        background: #eee; border-top: 1px solid #ccc; }
      #bar button { font-size: 15px; padding: 6px 14px; }
      #cardLabel { font-variant-numeric: tabular-nums; }
      #note { margin-left: auto; color: #888; font-size: 12px; }
      .field[contenteditable] { cursor: text; }
      .field .sel { background: #000; color: #fff; }
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
      <div id="menus"></div>
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
          const t0 = performance.now();
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
          const t1 = performance.now();
          const module = await WebAssembly.compile(bytes);
          const t2 = performance.now();
          await init({ module });
          const t3 = performance.now();
          console.info('Contrapt engine: ' + (bytes.length / 1048576).toFixed(1) + ' MB, download '
            + Math.round(t1 - t0) + ' ms, compile ' + Math.round(t2 - t1) + ' ms, boot '
            + Math.round(t3 - t2) + ' ms');
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
      // scriptID -> true for RICH fields (Markdown source) — applyState
      // re-renders these as Markdown instead of plain text.
      let richFields = {};

      // Rich fields hold Markdown source; render the same subset the app's
      // MarkdownHTML does (headings, bullets, links, bold/italic/code) with
      // DOM nodes — never innerHTML from stack text. A card: link goes to
      // the card; web links open a new tab.
      // An image part's source: an exported asset by name, or — after
      // `import picture from url` — the URL itself.
      function imageSrc(name) {
        name = name || '';
        return /^https?:/i.test(name) ? name : 'assets/' + name;
      }
      function followHref(href) {
        const h = String(href || '');
        if (h.toLowerCase().startsWith('card:')) {
          const ref = h.slice(5).trim();
          const n = Number(ref);
          let target = (ref !== '' && !isNaN(n)) ? n - 1
            : stack.cards.findIndex(c => (c.name || '').toLowerCase() === ref.toLowerCase());
          if (target >= 0 && target < stack.cards.length) go(target);
        } else if (/^https?:|^mailto:|^tel:/i.test(h)) {
          window.open(h, '_blank', 'noopener');
        }
      }
      function mdInline(parent, text) {
        const pattern = /`([^`]+)`|\\[([^\\]]+)\\]\\(([^)]+)\\)|\\*\\*([^*]+)\\*\\*|\\*([^*]+)\\*/g;
        let last = 0, m;
        while ((m = pattern.exec(text))) {
          if (m.index > last) parent.appendChild(document.createTextNode(text.slice(last, m.index)));
          if (m[1] != null) { const c = document.createElement('code'); c.textContent = m[1]; parent.appendChild(c); }
          else if (m[2] != null) {
            const a = document.createElement('a');
            mdInline(a, m[2]); a.href = '#';
            const href = m[3];
            a.onclick = (ev) => { ev.preventDefault(); ev.stopPropagation(); followHref(href); };
            parent.appendChild(a);
          }
          else if (m[4] != null) { const b = document.createElement('strong'); mdInline(b, m[4]); parent.appendChild(b); }
          else if (m[5] != null) { const i = document.createElement('em'); mdInline(i, m[5]); parent.appendChild(i); }
          last = m.index + m[0].length;
        }
        if (last < text.length) parent.appendChild(document.createTextNode(text.slice(last)));
      }
      function renderMarkdown(el, text) {
        el.textContent = '';
        el.dataset.md = text || '';
        let started = false;
        String(text || '').split('\\n').forEach(line => {
          const row = document.createElement('div');
          let body = line;
          const heading = line.match(/^(#{1,3})\\s+(.*)$/);
          if (heading) {
            row.style.fontWeight = 'bold';
            row.style.fontSize = (heading[1].length === 1 ? 1.7 : heading[1].length === 2 ? 1.4 : 1.2) + 'em';
            row.style.lineHeight = '1.2';
            row.style.margin = '0.3em 0 0.15em';
            body = heading[2];
          } else if (/^[-*]\\s+/.test(line)) {
            body = '• ' + line.replace(/^[-*]\\s+/, '');
          }
          if (body === '') {
            if (!started) return; // leading blanks render as nothing
            row.appendChild(document.createElement('br'));
          } else {
            started = true;
            mdInline(row, body);
          }
          el.appendChild(row);
        });
      }

      function fontFamily(d) {
        if (d === 'serif') return 'Palatino, "Palatino Linotype", "Book Antiqua", Georgia, serif';
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
        if (fmt.isOutline) { el.style.color = '#fff'; el.style.webkitTextStroke = '1px #000'; }
        el.style.justifyContent = el.style.textAlign =
          fmt.align === 'center' ? 'center' : fmt.align === 'right' ? 'right' : 'left';
      }
      // The field's grouped character ranges (HyperCard's group text style) as
      // [start, end) pairs, split at line breaks so a group never spans lines.
      // Each character's group state comes from the style run covering it,
      // falling back to the field's base format. Mirrors the native
      // FieldClickHitTest. Returns [] for ungrouped fields (the common case).
      function groupedRanges(f) {
        const text = f.text || '';
        const n = text.length;
        if (!n) return [];
        const base = !!(f.format && f.format.isGroup);
        const runs = (f.styleRuns || []).slice().sort((a, b) => a.start - b.start);
        function groupedAt(i) {
          let g = base;
          for (const r of runs) { if (r.start <= i) g = !!(r.format && r.format.isGroup); else break; }
          return g;
        }
        const ranges = [];
        let s = -1;
        for (let i = 0; i <= n; i++) {
          const on = i < n && text[i] !== '\\n' && groupedAt(i);
          if (on && s < 0) s = i;
          else if (!on && s >= 0) { ranges.push([s, i]); s = -1; }
        }
        return ranges;
      }
      function missingIconBox() {
        const box = document.createElement('div');
        box.className = 'icon-missing';
        box.title = 'Icon not available';
        return box;
      }
      // Styled text runs (per-chunk textFont/textSize/textStyle) as spans:
      // the base format covers any gap before the first run; each run styles
      // from its start to the next run's start.
      function setRunStyledText(el, text, runs, baseFormat) {
        el.textContent = '';
        const sorted = runs.slice().sort((a, b) => a.start - b.start);
        let cursor = 0;
        function emit(upTo, fmt) {
          if (upTo <= cursor) return;
          const span = document.createElement('span');
          styleText(span, fmt);
          span.style.display = 'inline';
          span.textContent = text.slice(cursor, upTo);
          el.appendChild(span);
          cursor = upTo;
        }
        for (let i = 0; i < sorted.length; i++) {
          emit(Math.min(sorted[i].start, text.length), i === 0 ? baseFormat : sorted[i - 1].format);
          if (cursor >= text.length) return;
        }
        emit(text.length, sorted.length ? sorted[sorted.length - 1].format : baseFormat);
      }
      function paint(asset) {
        if (!asset) return null;
        const im = document.createElement('img');
        im.className = 'paint'; im.src = 'assets/' + asset;
        return im;
      }
      // `overlay` is the owning card's backgroundFieldContent — a background
      // layer's non-sharedText field shows THIS card's text (the shared part
      // itself stores none).
      function renderPart(p, overlay) {
        const d = document.createElement('div');
        d.className = 'part';
        if (p.scriptID != null) { d.dataset.scriptId = p.scriptID; partEls[p.scriptID] = d; }
        d.style.left = p.frame.x + 'px'; d.style.top = p.frame.y + 'px';
        d.style.width = p.frame.width + 'px'; d.style.height = p.frame.height + 'px';
        if (p.enabled === false) d.classList.add('disabled');
        if (p.visible === false) { d.style.display = 'none'; return d; }
        // Accessible name — mirrors HyperTalk's Accessibility rules (part name
        // first), so a screen reader can announce each part.
        const accName = (p.name && p.name.trim()) || '';
        if (p.type === 'field') {
          const f = p.field || {};
          d.className += ' field ' + (f.style || 'rectangle');
          if (accName) d.setAttribute('aria-label', accName);
          if (f.kind !== 'rich' && !f.lockText) d.setAttribute('role', 'textbox');
          // Custom field colors (textColor/borderColor properties) — names
          // and #RRGGBB are both valid CSS.
          if (f.textColor) d.style.color = f.textColor;
          if (f.borderColor) d.style.borderColor = f.borderColor;
          styleText(d, f.format);
          // Imported HyperCard per-field line height — how tightly-set
          // stacks (the Tour) keep their vertical layout.
          if (f.textHeight) d.style.lineHeight = f.textHeight + 'px';
          const perCard = overlay && !f.sharedText ? overlay[p.id] : null;
          const text = (perCard ? perCard.text : f.text) || '';
          const runs = perCard ? (perCard.styleRuns || []) : (f.styleRuns || []);
          // Styled runs render as spans in LOCKED fields (editable fields stay
          // plain text so contentEditable editing isn't fighting markup).
          if (f.wideMargins) d.style.padding = '18px';
          if (f.kind === 'rich') { d.classList.add('rich'); richFields[p.scriptID] = true; renderMarkdown(d, text); }
          else if (runs.length && f.lockText) setRunStyledText(d, text, runs, f.format);
          else d.textContent = text;
          // A scrolling field starts at its stored scroll offset (layout must
          // exist first, hence the frame callback).
          if (f.style === 'scrolling' && f.scroll) {
            requestAnimationFrame(() => { d.scrollTop = f.scroll; });
          }
          // HyperCard "group" text style: the character ranges that click as a
          // unit, so the click handler can return the whole run as clickText
          // (the clickable-phrase navigation idiom). Stashed per-field.
          const groups = groupedRanges(f);
          if (groups.length) d.dataset.groups = JSON.stringify(groups);
          // Unlocked plain fields become editable once the engine is live.
          if (f.kind !== 'rich' && !f.lockText) d.dataset.editable = '1';
        } else if (p.type === 'button') {
          const b = p.button || {};
          d.className += ' button ' + (b.style || 'roundRect') + (b.hilite ? ' hilite' : '');
          // A div-as-button is invisible to assistive tech without this — give
          // it the button role, a spoken name (vital for icon-only buttons),
          // and keyboard focusability.
          d.setAttribute('role', 'button');
          d.setAttribute('aria-label', accName || b.title || 'Button');
          if (p.enabled === false) d.setAttribute('aria-disabled', 'true');
          else d.tabIndex = 0;
          // Custom button colors (fillColor/borderColor properties) — color
          // names and #RRGGBB are both valid CSS. A hilited button keeps its
          // inverse-video look (the .hilite class), so no inline fill then.
          if (b.fillColor && !b.hilite) d.style.background = b.fillColor;
          if (b.borderColor) d.style.borderColor = b.borderColor;
          if (b.textColor && !b.hilite) d.style.color = b.textColor;
          styleText(d, b.format);
          // Button titles center whatever the text format says (as the app
          // renders them); checkbox/radio lay out left with a glyph box.
          const isToggle = b.style === 'checkbox' || b.style === 'radio';
          d.style.justifyContent = isToggle ? 'flex-start' : 'center';
          d.style.textAlign = isToggle ? 'left' : 'center';
          if (isToggle) {
            const box = document.createElement('span');
            box.className = 'toggle';
            d.appendChild(box);
          }
          // An icon stacks above the title and scales to fit, as the app
          // lays buttons out (CardView's VStack).
          const iconName = b.iconAsset || (b.iconSymbol ? 'symbol-' + b.iconSymbol + '.png' : null);
          if (iconName) {
            d.classList.add('has-icon');
            const im = document.createElement('img');
            im.className = 'icon'; im.src = 'assets/' + iconName;
            // A missing asset file degrades to the same placeholder as a
            // missing icon resource (a symbol PNG from an older export just
            // leaves the title).
            im.onerror = () => { b.iconSymbol ? im.remove() : im.replaceWith(missingIconBox()); };
            d.appendChild(im);
          } else if (b.iconMissing) {
            d.appendChild(missingIconBox());
          }
          if (b.showName !== false && b.title) {
            const t = document.createElement('span'); t.className = 'title';
            t.textContent = b.title;
            d.appendChild(t);
          }
        } else if (p.type === 'label') {
          d.className += ' label'; d.textContent = (p.label && p.label.text) || '';
        } else if (p.type === 'image') {
          const im = document.createElement('img');
          im.style.width = '100%'; im.style.height = '100%';
          im.style.imageRendering = 'pixelated';
          im.alt = accName || 'Image';
          im.src = imageSrc(p.image && p.image.assetName);
          im.dataset.src = im.getAttribute('src');
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
      function buildLayer(card) {
        const bg = bgById[card.backgroundID];
        const layer = document.createElement('div');
        layer.className = 'layer';
        if (bg) {
          const bp = paint(bg.paintImageAsset);
          if (bp) {
            bp.classList.add('bg-paint');
            if (bg.showPicture === false) bp.style.display = 'none';
            layer.appendChild(bp);
          }
          (bg.parts || []).forEach(p => layer.appendChild(renderPart(p, card.backgroundFieldContent || {})));
        }
        const cp = paint(card.paintImageAsset);
        if (cp) {
          cp.classList.add('card-paint');
          if (card.showPicture === false) cp.style.display = 'none';
          layer.appendChild(cp);
        }
        (card.parts || []).forEach(p => layer.appendChild(renderPart(p)));
        return layer;
      }
      function render(fx) {
        const previous = Array.from(root.querySelectorAll('.layer')).pop() || null;
        const card = stack.cards[idx];
        partEls = {};
        richFields = {};
        const layer = buildLayer(card);
        root.style.width = W + 'px'; root.style.height = H + 'px';
        if (fx && fx.kind && fx.kind !== 'plain' && previous) {
          playEffect(fx, previous, layer);
        } else {
          root.innerHTML = '';
          root.appendChild(layer);
        }
        label.textContent = 'Card ' + (idx + 1) + ' of ' + stack.cards.length +
          (card.name ? ' — ' + card.name : '');
        fit();
        if (engineActive) enableFieldEditing();
      }

      // --- Visual effects ----------------------------------------------------
      // `visual effect <kind> [direction] [speed]` before a `go`: the incoming
      // layer animates over the outgoing one (closing variants animate the
      // outgoing layer away instead), with the app's timing curve and speeds.
      const FX_MS = { verySlow: 1300, slow: 900, normal: 500, fast: 280, veryFast: 120 };
      function playEffect(fx, oldLayer, newLayer) {
        const ms = FX_MS[fx.speed] || 500;
        const dir = fx.direction || '';
        const closing = dir === 'close' || dir === 'in';
        root.appendChild(newLayer);
        if (closing) root.appendChild(oldLayer);   // outgoing animates on top
        const el = (closing ? oldLayer : newLayer).style;
        const reveal = closing ? (p => 1 - p) : (p => p);
        const finish = () => {
          oldLayer.remove();
          const s = newLayer.style;
          s.opacity = ''; s.transform = ''; s.clipPath = '';
          s.maskImage = ''; s.webkitMaskImage = '';
          s.maskSize = ''; s.webkitMaskSize = '';
        };
        function tween(frame) {
          const t0 = performance.now();
          frame(0);
          function step(now) {
            const t = Math.min(1, (now - t0) / ms);
            const p = t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;  // ease-in-out
            frame(p);
            if (t < 1) requestAnimationFrame(step); else finish();
          }
          requestAnimationFrame(step);
        }
        switch (fx.kind) {
          case 'dissolve':
            tween(p => { el.opacity = reveal(p); });
            break;
          case 'zoom':
            tween(p => { const r = reveal(p); el.opacity = r; el.transform = 'scale(' + r + ')'; });
            break;
          case 'scroll': {
            const from = dir === 'right' ? [-W, 0] : dir === 'up' ? [0, H] : dir === 'down' ? [0, -H] : [W, 0];
            tween(p => { const r = 1 - p; el.transform = 'translate(' + (from[0] * r) + 'px,' + (from[1] * r) + 'px)'; });
            break;
          }
          case 'wipe':
            tween(p => {
              const r = (1 - p) * 100;
              el.clipPath = dir === 'right' ? 'inset(0 ' + r + '% 0 0)'
                : dir === 'up' ? 'inset(' + r + '% 0 0 0)'
                : dir === 'down' ? 'inset(0 0 ' + r + '% 0)'
                : 'inset(0 0 0 ' + r + '%)';
            });
            break;
          case 'iris':
            tween(p => { el.clipPath = 'circle(' + (reveal(p) * 75) + '% at 50% 50%)'; });
            break;
          case 'barnDoor':
            tween(p => { const r = (1 - reveal(p)) * 50; el.clipPath = 'inset(0 ' + r + '% 0 ' + r + '%)'; });
            break;
          case 'venetianBlinds': {
            const slat = H / 12;
            tween(p => {
              const on = Math.max(0.01, reveal(p) * slat);
              const m = 'repeating-linear-gradient(to bottom, black 0 ' + on + 'px, transparent ' + on + 'px ' + slat + 'px)';
              el.webkitMaskImage = m; el.maskImage = m;
            });
            break;
          }
          case 'checkerboard': {
            // HyperCard's two-phase checker: half the squares, then the rest.
            const m = 'repeating-conic-gradient(black 0 25%, transparent 0 50%)';
            el.webkitMaskImage = m; el.maskImage = m;
            el.webkitMaskSize = el.maskSize = (W / 4) + 'px ' + (H / 3) + 'px';
            setTimeout(finish, ms / 2);
            break;
          }
          default:
            finish();
        }
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
          // HyperCard's field-editing lifecycle: openField on focus; on blur,
          // closeField when the text changed, else exitField.
          el.addEventListener('focus', () => {
            el.dataset.openText = el.textContent;
            handle(engine.sendToPart('openField', Number(el.dataset.scriptId)));
          });
          el.addEventListener('blur', () => {
            const changed = el.textContent !== el.dataset.openText;
            handle(engine.sendToPart(changed ? 'closeField' : 'exitField', Number(el.dataset.scriptId)));
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
      // The engine's LIVE card count — scripts make and delete cards, so
      // navigation must wrap by this once the engine is running.
      let engineCardCount = 0;

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
        if (state.cardCount) engineCardCount = state.cardCount;
        // A part the engine no longer has was deleted by a script — hide its
        // element. (Per-part visibility below re-shows the live ones;
        // runtime-CREATED parts still need the state renderer — roadmap.)
        const live = new Set((state.backgroundParts || []).concat(state.cardParts || []).map(rp => rp.scriptID));
        Object.keys(partEls).forEach(id => {
          if (!live.has(Number(id))) partEls[id].style.display = 'none';
        });
        (state.backgroundParts || []).concat(state.cardParts || []).forEach(rp => {
          const el = partEls[rp.scriptID];
          if (!el) return;
          el.style.display = rp.visible === false ? 'none' : '';
          el.classList.toggle('disabled', rp.enabled === false);
          if (rp.kind === 'field' && rp.scroll != null && el !== document.activeElement
              && Math.abs(el.scrollTop - rp.scroll) > 1) {
            el.scrollTop = rp.scroll;
          }
          if (rp.kind === 'field' || rp.kind === 'label') {
            // Never clobber the field the visitor is typing in.
            if (el === document.activeElement) return;
            const text = rp.text || '';
            // A rich field re-renders its Markdown when the text changes
            // (e.g. a script set the link of a chunk).
            if (richFields[rp.scriptID]) {
              if (el.dataset.md !== text) renderMarkdown(el, text);
              return;
            }
            if (rp.selStart != null && rp.selEnd != null && rp.selEnd > rp.selStart) {
              // The script selection (`select line 2 of field 1`): show the
              // range highlighted, HyperCard-style.
              el.textContent = '';
              el.appendChild(document.createTextNode(text.slice(0, rp.selStart)));
              const mark = document.createElement('span');
              mark.className = 'sel';
              mark.textContent = text.slice(rp.selStart, rp.selEnd);
              el.appendChild(mark);
              el.appendChild(document.createTextNode(text.slice(rp.selEnd)));
            } else if (el.textContent !== text || el.querySelector('.sel')) {
              el.textContent = text;
            }
          } else if (rp.kind === 'image') {
            const im = el.querySelector('img');
            if (im && rp.asset != null) {
              const want = imageSrc(rp.asset);
              if (im.dataset.src !== want) { im.dataset.src = want; im.src = want; }
            }
          } else if (rp.kind === 'button') {
            el.classList.toggle('hilite', !!rp.hilite);
            // .title specifically — a checkbox's first span is its glyph box.
            const span = el.querySelector('span.title');
            if (span) span.textContent = rp.text || '';
          }
        });
        // `show/hide picture` — blank the paint layers without a re-render.
        const layer = Array.from(root.querySelectorAll('.layer')).pop();
        if (layer) {
          const cardPaint = layer.querySelector('.card-paint');
          if (cardPaint) cardPaint.style.display = state.cardShowPicture === false ? 'none' : '';
          const bgPaint = layer.querySelector('.bg-paint');
          if (bgPaint) bgPaint.style.display = state.backgroundShowPicture === false ? 'none' : '';
        }
        renderMenus(state.menus || []);
        applyViewport(state.viewportWidth, state.viewportHeight);
      }

      // The scripted menu strip (`create menu` / `put … into menu`), same
      // placement as the app's: above the card. An item click dispatches
      // doMenu through the engine.
      function renderMenus(menus) {
        const strip = document.getElementById('menus');
        document.body.classList.toggle('has-menus', menus.length > 0);
        const signature = JSON.stringify(menus);
        if (strip.dataset.signature === signature) return;
        strip.dataset.signature = signature;
        strip.textContent = '';
        menus.forEach(menu => {
          const m = document.createElement('div');
          m.className = 'menu' + (menu.enabled === false ? ' disabled' : '');
          m.appendChild(document.createTextNode(menu.name));
          const drop = document.createElement('div');
          drop.className = 'drop';
          (menu.items || []).forEach(item => {
            const el = document.createElement('div');
            el.className = 'item' + (item.enabled === false ? ' disabled' : '');
            el.textContent = (item.checkMark ? '✓ ' : '') + item.name;
            if (item.name === '-') { el.textContent = '—'; el.className += ' disabled'; }
            el.onclick = ev => {
              ev.stopPropagation();
              m.classList.remove('open');
              if (engine) handle(engine.message('doMenu "' + item.name.replace(/"/g, '') + '"'));
            };
            drop.appendChild(el);
          });
          m.appendChild(drop);
          m.onclick = () => {
            const wasOpen = m.classList.contains('open');
            strip.querySelectorAll('.menu.open').forEach(x => x.classList.remove('open'));
            if (!wasOpen) m.classList.add('open');
          };
          strip.appendChild(m);
        });
      }
      document.addEventListener('click', ev => {
        if (!ev.target.closest('#menus')) {
          document.querySelectorAll('#menus .menu.open').forEach(x => x.classList.remove('open'));
        }
      });

      // The card-window viewport crop (`set the rect of card window`): the
      // card element shrinks to the viewport, clipping the oversized card at
      // its top-left — the classic big-card-small-window idiom.
      function applyViewport(width, height) {
        const vw = width || W, vh = height || H;
        root.style.width = vw + 'px';
        root.style.height = vh + 'px';
      }

      // Per-stack localStorage key for the persistent `stackData` store.
      const stackDataKey = 'contrapt.stackData.' + (stack.id || stack.name || 'stack');
      // Seed the engine's store from localStorage; the wasm entry passes
      // window.__STACK_DATA__ to StackEngine(persistentData:).
      try { window.__STACK_DATA__ = localStorage.getItem(stackDataKey) || ''; }
      catch (e) { window.__STACK_DATA__ = ''; }

      function applyEffects(effects) {
        (effects || []).forEach(e => {
          if (e.type === 'message') note.textContent = e.text;
          else if (e.type === 'beep') beep();
          else if (e.type === 'persist') {
            // `stackData` was written — flush it to localStorage so it survives
            // a reload (the stack file itself is never modified).
            try { localStorage.setItem(stackDataKey, e.encoded || ''); } catch (err) {}
          }
          else if (e.type === 'scheduleSend') {
            // `send … in <time>`: the page owns the timer, so pending sends
            // die with the page — exactly the stack-close rule. An engine
            // built before deliverScheduled just drops the send.
            setTimeout(() => {
              if (engine && engine.deliverScheduled)
                handle(engine.deliverScheduled(e.message, JSON.stringify(e.arguments || []),
                                               e.partScriptID == null ? -1 : e.partScriptID,
                                               e.cardScriptID));
            }, Math.max(0, (e.afterSeconds || 0) * 1000));
          }
          // 'navigate' is reflected by the returned state's cardIndex below.
        });
      }

      async function handle(pending) {
        let res;
        try { res = JSON.parse(await pending); } catch (e) { note.textContent = 'Engine error.'; return; }
        if (res.error) { note.textContent = 'Error: ' + res.error; return; }
        if (res.state && res.state.cardIndex !== idx) {
          idx = res.state.cardIndex;
          const nav = (res.effects || []).find(e => e.type === 'navigate' && e.effects && e.effects.length);
          render(nav ? nav.effects[0] : undefined);
        }
        if (res.state && res.state.theme) applyTheme(res.state.theme);
        applyState(res.state);
        applyEffects(res.effects);
        if (res.result != null) note.textContent = res.result;
      }

      function go(n) {
        const total = (engineActive && engineCardCount) ? engineCardCount : stack.cards.length;
        const wrapped = (n + total) % total;
        if (engine) { handle(engine.openCard(wrapped)); } else { idx = wrapped; render(); }
      }
      document.getElementById('prev').onclick = () => go(idx - 1);
      document.getElementById('next').onclick = () => go(idx + 1);
      window.addEventListener('resize', fit);
      document.title = stack.name || 'Contrapt Stack';

      // --- Theme -------------------------------------------------------------
      // Mirror of HyperTalk's ThemeSpec: Classic uses the :root defaults;
      // Modern Light/Dark override the CSS variables. `set the theme` at runtime
      // re-applies via CardState.theme in handle().
      const THEMES = {
        light: { '--surface': '#FFFFFF', '--ink': '#1C1C1E', '--accent': '#007AFF', '--border': '#D1D1D6', '--padding': '#F2F2F7' },
        dark:  { '--surface': '#1C1C1E', '--ink': '#F2F2F7', '--accent': '#0A84FF', '--border': '#3A3A3C', '--padding': '#000000' },
      };
      let currentTheme = null;
      function applyTheme(name) {
        if (name === currentTheme) return;
        currentTheme = name;
        const root = document.documentElement;
        ['--surface', '--ink', '--accent', '--border', '--padding'].forEach(v => root.style.removeProperty(v));
        const t = THEMES[name];
        if (t) for (const k in t) root.style.setProperty(k, t[k]);
        root.style.colorScheme = (name === 'dark') ? 'dark' : 'light';
      }
      applyTheme(stack.theme || 'classic');

      render();

      function activateEngine() {
        engine = window.ContraptEngine;
        if (!engine || engineActive) return;
        engineActive = true;
        note.textContent = '';
        enableFieldEditing();
        // A click on any part sends mouseUp along its message path. Field
        // clicks also carry which line/word they landed on (the clickLine /
        // clickText), via the browser's own text hit-testing.
        root.addEventListener('click', ev => {
          const partEl = ev.target.closest('.part');
          if (!partEl || partEl.dataset.scriptId == null) return;
          let line = null, word = null;
          if (partEl.classList.contains('field')) {
            const caret = document.caretRangeFromPoint
              ? document.caretRangeFromPoint(ev.clientX, ev.clientY)
              : null;
            const pos = caret ? { node: caret.startContainer, offset: caret.startOffset }
              : document.caretPositionFromPoint
                ? (c => c && { node: c.offsetNode, offset: c.offset })(document.caretPositionFromPoint(ev.clientX, ev.clientY))
                : null;
            if (pos && partEl.contains(pos.node)) {
              const full = partEl.textContent;
              const before = full.slice(0, pos.offset);
              line = (before.match(/\\n/g) || []).length + 1;
              // Grouped text (HyperCard's group style): a click in a grouped
              // range returns the whole run, not just the word. Otherwise the
              // word under the click, scanning out to whitespace.
              const groups = partEl.dataset.groups ? JSON.parse(partEl.dataset.groups) : [];
              const group = groups.find(([gs, ge]) => pos.offset >= gs && pos.offset < ge);
              if (group) {
                word = full.slice(group[0], group[1]).trim();
              } else {
                let s = pos.offset, e = pos.offset;
                while (s > 0 && !/\\s/.test(full[s - 1])) s--;
                while (e < full.length && !/\\s/.test(full[e])) e++;
                word = full.slice(s, e);
              }
            }
          }
          handle(engine.mouseUp(Number(partEl.dataset.scriptId), line, word));
        });
        // Keyboard activation: a focused button (role="button", tabindex=0)
        // fires its mouseUp on Enter/Space, so the stack is operable without a
        // mouse (editable fields keep the keys for typing).
        root.addEventListener('keydown', ev => {
          if (ev.key !== 'Enter' && ev.key !== ' ') return;
          const partEl = ev.target.closest('.part.button');
          if (!partEl || partEl.dataset.scriptId == null) return;
          if (partEl.classList.contains('disabled')) return;
          ev.preventDefault();
          handle(engine.mouseUp(Number(partEl.dataset.scriptId), null, null));
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

      // --- Networking --------------------------------------------------------
      // `url`/`post`/`delete url` run through the browser's fetch(), so they are
      // subject to the server's CORS policy — a page can't proxy around it, and
      // there's no in-page consent prompt (the browser's own model governs it).
      // The engine's EngineInteraction.httpRequest bridge resolves this promise
      // with { body, status, headers, error }.
      window.ContraptHttp = {
        async request(method, url, body, headers, timeout) {
          const controller = new AbortController();
          const timer = timeout > 0 ? setTimeout(() => controller.abort(), timeout * 1000) : null;
          try {
            const response = await fetch(url, {
              method,
              headers: headers || {},
              body: (body === null || body === undefined || method === 'GET') ? undefined : body,
              signal: controller.signal,
            });
            const text = await response.text();
            const responseHeaders = {};
            response.headers.forEach((value, key) => { responseHeaders[key] = value; });
            return { body: text, status: response.status, headers: responseHeaders, error: null };
          } catch (e) {
            const message = (e && e.name === 'AbortError')
              ? 'The request timed out.'
              : 'Couldn’t reach ' + url + ' (the server may not allow cross-origin requests).';
            return { body: '', status: 0, headers: {}, error: message };
          } finally {
            if (timer) clearTimeout(timer);
          }
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
