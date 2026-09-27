//
//  RichTextFieldView.swift
//  Contrapt
//

import SwiftUI
import WebKit

/// A link followed from a rich field.
enum FieldLink {
    /// An internal `card:` link — a card name or number to `go` to.
    case card(String)
    /// A web/mail/tel link, to open in the system browser on tap.
    case external(URL)
}

/// Renders a rich field's Markdown in a `WKWebView`, trapping link taps.
///
/// Privacy (D7): the HTML (from `MarkdownHTML`) has no remote references and
/// JavaScript is disabled, so the view fetches nothing. Only explicit link
/// taps do anything, and they're routed out through `onFollowLink` — card
/// links to `go`, web links to the system browser — never loaded in place.
struct RichFieldView: View {
    let markdown: String
    var fontDesign: FontDesign = .standard
    var size: Double = 17
    var style: FieldStyle = .rectangle
    /// The card's highlight as a CSS link color, or nil for the default.
    var linkColorHex: String? = nil
    var onFollowLink: (FieldLink) -> Void

    var body: some View {
        // The web view is transparent; the chrome supplies the fill/border so
        // a transparent field lets the card show through the rendered text.
        RichTextWebView(markdown: markdown, fontDesign: fontDesign, size: size, linkColorHex: linkColorHex, onFollowLink: onFollowLink)
            .fieldChrome(style: style)
    }
}

/// A full-screen Markdown editor for a rich field: the source on the left,
/// a live rendered preview on the right. Roomier than the inspector column,
/// for authoring longer content (Home cards, shipped stacks).
struct LargeMarkdownEditor: View {
    let title: String
    @Binding var markdown: String
    var fontDesign: FontDesign
    var size: Double

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                TextEditor(text: $markdown)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .padding(8)
                    .frame(maxWidth: .infinity)
                Divider()
                // Preview links don't navigate here (no card context); external
                // links stay inert while authoring.
                RichFieldView(markdown: markdown, fontDesign: fontDesign, size: size) { _ in }
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Color.cardBackdrop)
            }
            .navigationTitle(title)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 820, idealWidth: 1040, minHeight: 520, idealHeight: 720)
        #endif
    }
}

/// The web view itself, bridged for both platforms.
private struct RichTextWebView {
    let markdown: String
    var fontDesign: FontDesign
    var size: Double
    var linkColorHex: String? = nil
    var onFollowLink: (FieldLink) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFollowLink: onFollowLink) }

    fileprivate func makeWebView(_ coordinator: Coordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // No scripts are needed and none should run — belt with the braces of
        // having no remote content in the first place.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        // Transparent, so the field's chrome (or the card, when the style is
        // transparent) shows behind the rendered text.
        #if os(iOS)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        #elseif os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
        #endif
        load(into: webView, coordinator: coordinator)
        return webView
    }

    fileprivate func update(_ webView: WKWebView, _ coordinator: Coordinator) {
        coordinator.onFollowLink = onFollowLink
        if coordinator.lastRenderKey != renderKey {
            load(into: webView, coordinator: coordinator)
        }
    }

    /// Reload only when what affects the rendered HTML changes.
    private var renderKey: String { "\(fontDesign.rawValue)|\(size)|\(linkColorHex ?? "")|\(markdown)" }

    private func load(into webView: WKWebView, coordinator: Coordinator) {
        coordinator.lastRenderKey = renderKey
        webView.loadHTMLString(
            MarkdownHTML.document(from: markdown, fontDesign: fontDesign, size: size, linkColor: linkColorHex),
            baseURL: nil
        )
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onFollowLink: (FieldLink) -> Void
        var lastRenderKey: String?

        init(onFollowLink: @escaping (FieldLink) -> Void) {
            self.onFollowLink = onFollowLink
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            if navigationAction.navigationType == .linkActivated {
                switch url.scheme?.lowercased() {
                case "card":
                    let raw = String(url.absoluteString.dropFirst("card:".count))
                    let ref = (raw.removingPercentEncoding ?? raw)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
                    onFollowLink(.card(ref))
                case "http", "https", "mailto", "tel":
                    onFollowLink(.external(url))
                default:
                    break // unknown scheme: ignore
                }
                decisionHandler(.cancel)
                return
            }
            // Allow only our own inline content; block anything that would
            // reach the network.
            if url.scheme == nil || url.scheme == "about" || url.isFileURL {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }
}

#if os(iOS)
extension RichTextWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    func updateUIView(_ webView: WKWebView, context: Context) { update(webView, context.coordinator) }
}
#elseif os(macOS)
extension RichTextWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    func updateNSView(_ webView: WKWebView, context: Context) { update(webView, context.coordinator) }
}
#endif
