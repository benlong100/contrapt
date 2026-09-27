//
//  IconPicker.swift
//  Contrapt
//
//  Contrapt's button-icon library. HyperCard shipped a palette of bitmap ICON
//  resources; Contrapt can't ship those, so buttons draw an SF Symbol instead —
//  a large, always-available vector library, chosen here by name. Only the
//  symbol *name* is stored (a string, not a bundled asset).
//
//  SF Symbols aren't enumerable at runtime, so the catalog below is a curated
//  selection covering the common needs of a stack (navigation, documents,
//  media, tools, communication, shapes). Searchable by name.
//

import SwiftUI

enum IconLibrary {
    /// Curated SF Symbol names offered in the picker. Grouped loosely by theme
    /// for a sensible default order; search matches anywhere in the name.
    static let all: [String] = [
        // Navigation & home
        "house", "house.fill", "arrow.left", "arrow.right", "arrow.up", "arrow.down",
        "arrowshape.left.fill", "arrowshape.right.fill", "chevron.left", "chevron.right",
        "chevron.up", "chevron.down", "arrow.uturn.left", "arrow.uturn.right",
        "arrow.backward.circle.fill", "arrow.forward.circle.fill", "arrow.up.left", "arrow.up.right",
        "location", "location.fill", "map", "map.fill", "signpost.right", "point.topleft.down.curvedto.point.bottomright.up",
        // Documents & stacks
        "doc", "doc.fill", "doc.text", "doc.text.fill", "note.text", "book", "book.fill",
        "books.vertical", "books.vertical.fill", "rectangle.stack", "rectangle.stack.fill",
        "folder", "folder.fill", "tray", "tray.fill", "archivebox", "archivebox.fill",
        "list.bullet", "list.bullet.rectangle", "square.grid.2x2", "square.grid.3x3",
        // Editing & tools
        "pencil", "pencil.circle", "pencil.circle.fill", "square.and.pencil", "paintbrush",
        "paintbrush.fill", "paintpalette", "paintpalette.fill", "hammer", "hammer.fill",
        "wrench", "wrench.and.screwdriver", "scissors", "trash", "trash.fill", "eraser",
        "eyedropper", "ruler", "textformat", "bold", "italic", "underline", "highlighter",
        // Media & playback
        "play", "play.fill", "play.circle", "play.circle.fill", "pause", "pause.fill",
        "stop", "stop.fill", "backward.fill", "forward.fill", "speaker.wave.2.fill",
        "speaker.slash.fill", "music.note", "photo", "photo.fill", "camera", "camera.fill",
        "film", "video", "video.fill", "waveform",
        // Communication & people
        "envelope", "envelope.fill", "bubble.left", "bubble.left.fill", "phone", "phone.fill",
        "person", "person.fill", "person.2", "person.2.fill", "person.crop.circle",
        "bell", "bell.fill", "megaphone", "megaphone.fill", "paperplane", "paperplane.fill",
        // Time & data
        "calendar", "clock", "clock.fill", "alarm", "alarm.fill", "timer", "hourglass",
        "chart.bar", "chart.bar.fill", "chart.pie", "chart.pie.fill", "chart.line.uptrend.xyaxis",
        "sum", "number", "function", "percent", "creditcard", "dollarsign.circle",
        // Symbols & status
        "star", "star.fill", "heart", "heart.fill", "flag", "flag.fill", "bookmark",
        "bookmark.fill", "tag", "tag.fill", "pin", "pin.fill", "lightbulb", "lightbulb.fill",
        "checkmark", "checkmark.circle", "checkmark.circle.fill", "xmark", "xmark.circle",
        "xmark.circle.fill", "plus", "plus.circle", "plus.circle.fill", "minus", "minus.circle",
        "questionmark.circle", "questionmark.circle.fill", "info.circle", "info.circle.fill",
        "exclamationmark.triangle", "exclamationmark.triangle.fill", "magnifyingglass",
        "gearshape", "gearshape.fill", "slider.horizontal.3", "lock", "lock.fill",
        "lock.open", "key", "key.fill", "hand.point.up.left", "hand.point.up.left.fill",
        "hand.tap", "hand.tap.fill", "cursorarrow", "cursorarrow.rays",
        // Shapes
        "circle", "circle.fill", "square", "square.fill", "triangle", "triangle.fill",
        "diamond", "diamond.fill", "hexagon", "hexagon.fill", "seal", "seal.fill",
        "globe", "globe.americas.fill", "sparkles", "wand.and.stars", "moon", "moon.fill",
        "sun.max", "sun.max.fill", "cloud", "cloud.fill", "bolt", "bolt.fill",
    ]

    static func matches(_ query: String) -> [String] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter { $0.contains(q) }
    }
}

/// A sheet that picks an SF Symbol for a button's icon. `onSelect(nil)` removes
/// the icon.
struct IconPickerView: View {
    let current: String?
    let onSelect: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private let columns = [GridItem(.adaptive(minimum: 60), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(IconLibrary.matches(query), id: \.self) { name in
                        Button {
                            onSelect(name)
                            dismiss()
                        } label: {
                            Image(systemName: name)
                                .font(.system(size: 26))
                                .frame(width: 56, height: 56)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(name == current ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12))
                                )
                        }
                        .buttonStyle(.plain)
                        .help(name)
                    }
                }
                .padding()
            }
            .navigationTitle("Choose Icon")
            .searchable(text: $query, prompt: "Search icons")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Remove Icon", role: .destructive) {
                        onSelect(nil)
                        dismiss()
                    }
                    .disabled(current == nil)
                }
            }
        }
    }
}
