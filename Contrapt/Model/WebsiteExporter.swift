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
        // Also emit the data as a JS global. Opening index.html from a file://
        // URL blocks fetch() of a sibling file (local-file CORS), so the player
        // reads window.__STACK__ from a <script> (which loads fine locally) and
        // only falls back to fetch when the site is served over http.
        let dataJS = "window.__STACK__ = " + (String(data: json, encoding: .utf8) ?? "null") + ";\n"
            + "window.__ACTUAL_SIZE__ = " + (actualSize ? "true" : "false") + ";\n"
        entries["stack-data.js"] = Data(dataJS.utf8)
        entries["index.html"] = Data(indexHTML.utf8)
        entries["player.js"] = Data(playerJS.utf8)
        for name in stack.referencedAssetNames() {
            guard let data = assets[name] else { continue }
            entries["assets/\(name)"] = data
        }
        return entries
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
      <script src="player.js"></script>
    </body>
    </html>
    """

    static let playerJS = """
    (async function () {
      const stack = window.__STACK__ || await (await fetch('stack.json')).json();
      const bgById = {};
      (stack.backgrounds || []).forEach(b => { bgById[b.id] = b; });
      const W = stack.cardSize.width, H = stack.cardSize.height;
      const root = document.getElementById('card');
      const label = document.getElementById('cardLabel');
      let idx = 0;

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
        d.style.left = p.frame.x + 'px'; d.style.top = p.frame.y + 'px';
        d.style.width = p.frame.width + 'px'; d.style.height = p.frame.height + 'px';
        if (p.visible === false) { d.style.display = 'none'; return d; }
        if (p.type === 'field') {
          const f = p.field || {};
          d.className += ' field ' + (f.style || 'rectangle');
          styleText(d, f.format);
          d.textContent = f.text || '';
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
      }
      document.getElementById('prev').onclick = () => { idx = (idx - 1 + stack.cards.length) % stack.cards.length; render(); };
      document.getElementById('next').onclick = () => { idx = (idx + 1) % stack.cards.length; render(); };
      window.addEventListener('resize', fit);
      document.title = stack.name || 'Contrapt Stack';
      render();
    })();
    """
}
