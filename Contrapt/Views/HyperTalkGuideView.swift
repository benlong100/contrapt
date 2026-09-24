//
//  HyperTalkGuideView.swift
//  Contrapt
//

import SwiftUI
import HyperTalk

/// The in-app HyperTalk quick reference: the whole language on one
/// scrollable page, with live-colored examples.
struct HyperTalkGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    section("Handlers", body: "Scripts are made of handlers that answer messages. Tapping a part sends mouseDown, then mouseUp. Cards receive openCard when you arrive; the stack receives openStack when it opens.", example: """
                    on mouseUp
                      put "You tapped me!"
                    end mouseUp
                    """)

                    section("The message path", body: "A message goes to the tapped part first, then its card, the background, and the stack — the first handler wins. Words HyperTalk doesn't know travel the same path, so you can invent commands.", example: """
                    -- in a button:
                    on mouseUp
                      greet "Bill"
                    end mouseUp

                    -- in the card, background, or stack:
                    on greet who
                      put "Hello," && who & "!"
                    end greet
                    """)

                    section("put", body: "Puts a value into a variable or field — or, with no destination, into the Message Box. `after` and `before` append instead of replacing.", example: """
                    put 6 * 7 into answer
                    put "Hi" into field "Greeting"
                    put "!" after field "Greeting"
                    put "new" into background field 1
                    put field id 9 into safekeeping
                    put "slow" into word 2 of field "Notes"
                    put "third" into line 3 of field "Log"
                    put "shown in the Message Box"
                    """)

                    section("go", body: "Moves between cards, by position, number, or name.", example: """
                    go to next card
                    go to previous card
                    go to first card
                    go to card 3
                    go to card "Home"
                    """)

                    section("Functions and globals", body: "Define your own functions with `function … end`, call them with parentheses, and return a value. `the result` holds the last command's return. `global` shares a variable across handlers and across taps. Built-ins: length(x), random(n), round/trunc/abs, min/max, offset(a,b), charToNum/numToChar, the number of words/items/lines/chars of X, and the date / the long date / the time / the seconds / the ticks.", example: """
                    on mouseUp
                      put greet("Ada") into field "out"
                    end mouseUp

                    function greet who
                      return "Hello," && who
                    end greet

                    on tally
                      global count
                      put count + 1 into count
                    end tally
                    """)

                    section("Chunks", body: "Reach into text by character, word, item (comma-separated), or line — by number, by ordinal (first…tenth, last, middle), or by range. Chunks nest and work on any text, including fields. `set the itemDelimiter` changes what `item` splits on, so you can parse any delimited text.", example: """
                    put word 3 of "the quick brown fox"   -- brown
                    put the last word of field "Name"
                    put char 1 to 5 of field "Title"
                    put item 2 of "red,green,blue"        -- green
                    put line 3 of field "Log"
                    put the first char of the last word of s
                    set the itemDelimiter to "/"
                    put item 2 of "usr/local/bin"          -- local
                    """)

                    section("get and set", body: "Every object has properties. `set` changes them; `the … of …` reads them anywhere an expression fits; `get` reads one into the special variable `it`. Parts have name, visible, title or text, and geometry (left, top, right, bottom, width, height). Buttons also have style (roundRect, rectangle, shadow, opaque, transparent, checkbox, radio), showName, autoHilite, and hilite (the check-box/radio on-state). Fields have textFont (system, serif, monospaced, rounded), textSize, textStyle (bold, italic, underline, or plain), and textAlign (left, center, right). Cards have name, number, marked, cantDelete, and dontSearch; the stack has name, cards, width, and height. Refer to parts three ways: by name (button \"OK\"), by ordinal (field 1 — position among that kind, and `the number of` reads it back), or by permanent id (button id 6 — shown in the Inspector, and it survives renames). Add `card` or `background` before the kind to pick the layer: card field 1, background button \"Next\".", example: """
                    set the name of card field 1 to "blah"
                    set the visible of button "Secret" to false
                    set the width of field "Notes" to 400
                    set the title of button "OK" to "Go!"
                    get the name of this card
                    put it into field "Where"
                    if the left of button "Box" > 500 then beep
                    set the text of field id 9 to "found you"
                    go to card id 12
                    """)

                    section("if", body: "Single-line or block form, with optional else and else-if chains.", example: """
                    if field "Name" is empty then beep
                    if x > 10 then
                      put "big"
                    else if x > 5 then
                      put "medium"
                    else
                      put "small"
                    end if
                    """)

                    section("repeat", body: "Five shapes. `exit repeat` leaves early; `next repeat` skips ahead. A runaway loop is stopped safely.", example: """
                    repeat 5 times
                    repeat with i = 1 to 10
                    repeat with i = 10 down to 1
                    repeat while x < 100
                    repeat until field "Done" is "yes"
                    """)

                    section("Values and operators", body: "Everything is text, becoming a number or true/false as needed. Comparisons ignore case; & joins, && joins with a space. Also: + - * / div mod, and, or, not, contains, is, is not.", example: """
                    put "Hyper" & "Talk"          -- HyperTalk
                    put "Hello" && "world"        -- Hello world
                    if "10" > "9" then beep       -- numeric compare
                    if name contains "an" then beep
                    """)

                    section("Constants and more", body: "empty, space, comma, quote, return, tab, true, false. `beep` beeps (or `beep 3`). `exit mouseUp` ends a handler early. Comments start with two dashes.", example: """
                    put empty into field "Log"
                    put "a" & comma & space & "b"  -- a, b
                    beep 2                          -- twice
                    """)

                    section("Tips", body: "The Message Box (toolbar) runs any line you type in the current card's context — a calculator, a tester, a remote control. Check Script in the inspector finds mistakes before you run. Everything you do while editing can be undone.", example: nil)
                }
                .padding(24)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("HyperTalk Guide")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, body: String, example: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title2.bold())
            Text(body)
                .foregroundStyle(.secondary)
            if let example {
                Text(highlighted(example))
                    .font(.system(.callout, design: .monospaced))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.cardBackdrop, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    /// The same coloring the script editor uses, applied statically.
    private func highlighted(_ source: String) -> AttributedString {
        var result = AttributedString(source)
        for span in HyperTalk.syntaxSpans(in: source) {
            guard let range = Range(span.range, in: result) else { continue }
            switch span.kind {
            case .keyword: result[range].foregroundColor = .purple
            case .string: result[range].foregroundColor = .red
            case .number: result[range].foregroundColor = .blue
            case .comment: result[range].foregroundColor = .gray
            case .identifier, .symbol: break
            }
        }
        return result
    }
}

#Preview {
    HyperTalkGuideView()
}
