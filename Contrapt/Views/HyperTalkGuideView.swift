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

                    section("answer and ask", body: "`answer` shows a message with up to three buttons; the clicked button's label lands in `it`. `ask` shows a text prompt with an optional default; the entered text lands in `it` (empty if the user cancels, with `the result` set to \"Cancel\").", example: """
                    answer "Save changes?" with "Yes" or "No" or "Cancel"
                    if it is "Yes" then put "saving"

                    ask "What is your name?" with "friend"
                    put "Hello, " & it into field "Greeting"
                    """)

                    section("go", body: "Moves between cards, by position, number, or name.", example: """
                    go to next card
                    go to previous card
                    go to first card
                    go to card 3
                    go to card "Home"
                    go home
                    """)

                    section("add, subtract, multiply, divide", body: "Arithmetic commands that change a container in place — the classic HyperCard way to do math without `put … into`.", example: """
                    add 1 to counter
                    subtract 5 from field "Total"
                    multiply price by 1.08
                    divide total by count
                    """)

                    section("show, hide, push, pop", body: "`show` and `hide` flip a part's visibility (the same as `set the visible of …`). `push card` remembers the current card; `pop card` returns to it, and `pop card into <container>` reads the remembered card without going. A visual effect before a `pop` plays, just like `go`.", example: """
                    hide field "Answer"
                    show button "Next"
                    push card
                    go to card "Help"
                    pop card
                    """)

                    section("visual effect", body: "Queue a transition for the next `go`: dissolve, wipe or scroll (left/right/up/down), zoom or iris (open/close), plus barn door, checkerboard, and venetian blinds. Add a speed — slow, fast, very slow, very fast. Several queue up and play in order.", example: """
                    visual effect dissolve
                    go to next card

                    visual effect wipe left fast
                    go to card "Menu"

                    visual iris open slowly
                    go to first card
                    """)

                    section("find", body: "Searches every field in the stack for text, starting at the current card and wrapping around. On a hit it goes to that card and boxes the match; repeating the same `find` steps to the next one. Plain `find` matches the start of any word; `find chars` matches anywhere; `find word` and `find whole` match whole words; `find string` matches an exact run of characters. Add `in <field>` to search just one field. Afterwards `the result` is empty on a hit (\"not found\" on a miss), and `the foundText`, `the foundChunk`, `the foundLine`, and `the foundField` describe the match.", example: """
                    find "brown"                    -- word beginning with brown
                    find chars "ell" in field "Notes"
                    find whole "red car"
                    if the result is "not found" then beep
                    put the foundText into field "Hit"
                    """)

                    section("Functions and globals", body: "Define your own functions with `function … end`, call them with parentheses, and return a value. `the result` holds the last command's return. `global` shares a variable across handlers and across taps. Built-ins: length(x), random(n), round/trunc/abs, min/max, sum/average (of a list or arguments), offset(a,b), charToNum/numToChar, math functions sqrt, sin, cos, tan, atan, exp/exp1/exp2, ln/ln1, log2, annuity(rate,n), compound(rate,n) — each also readable as `the sqrt of x` — the number of words/items/lines/chars of X, and the date / the long date / the time / the seconds / the ticks.", example: """
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

                    section("Dates and times", body: "`the date`, `the long date`, `the abbreviated date`, `the time`, `the long time`, `the seconds` (since 1970), and `the ticks` read the clock. `convert` reformats between them: give a container to rewrite it in place, or a bare value to land the result in `it`. Formats are seconds, dateItems (year,month,day,hour,minute,second,weekday), short/long/abbreviated date, and short/long time — combine date and time with `and`. Add `from <format>` when the input's format is ambiguous.", example: """
                    put the long date          -- Sunday, January 1, 2034
                    convert the date to seconds
                    convert field "when" to short date and short time
                    put "2034,1,1,0,0,0" into t
                    convert t from dateItems to long date
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

                    section("get and set", body: "Every object has properties. `set` changes them; `the … of …` reads them anywhere an expression fits; `get` reads one into the special variable `it`. Parts have name, visible, title or text, and geometry (left, top, right, bottom, width, height). Buttons also have style (roundRect, rectangle, shadow, opaque, transparent, checkbox, radio), showName, autoHilite, and hilite (the check-box/radio on-state). Fields have textFont (system, serif, monospaced, rounded), textSize, textStyle (bold, italic, underline, or plain), textAlign (left, center, right), style (transparent, opaque, rectangle, shadow), and the plain-field options lockText (locked fields send mouseUp to their script instead of taking text), showLines, and wideMargins. Cards have name, number, marked, cantDelete, and dontSearch; the stack has name, cards, width, height, fullScreen (open filling the screen), and paddingColor (the fill behind the card — a color name or #RRGGBB). Refer to parts three ways: by name (button \"OK\"), by ordinal (field 1 — position among that kind, and `the number of` reads it back), or by permanent id (button id 6 — shown in the Inspector, and it survives renames). Add `card` or `background` before the kind to pick the layer: card field 1, background button \"Next\". `me` is the object whose script is running; `the target` is the object first tapped — so a shared card handler can tell which button sent the message.", example: """
                    set the name of card field 1 to "blah"
                    set the visible of button "Secret" to false
                    set the width of field "Notes" to 400
                    set the title of button "OK" to "Go!"
                    get the name of this card
                    put it into field "Where"
                    if the left of button "Box" > 500 then beep
                    set the text of field id 9 to "found you"
                    go to card id 12
                    set the hilite of me to true
                    put the target into field "Clicked"
                    set the fullScreen of this stack to true
                    set the paddingColor of this stack to "black"
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

                    section("wait", body: "Pauses the handler: a duration in seconds or ticks (a tick is 1/60 second; a bare number is ticks), or until/while a condition.", example: """
                    wait 2 seconds
                    wait 30 ticks
                    wait until field "Ready" is "yes"
                    wait while field "Busy" is "yes"
                    """)

                    section("repeat", body: "Five shapes. `exit repeat` leaves early; `next repeat` skips ahead. A runaway loop is stopped safely.", example: """
                    repeat 5 times
                    repeat with i = 1 to 10
                    repeat with i = 10 down to 1
                    repeat while x < 100
                    repeat until field "Done" is "yes"
                    """)

                    section("Values and operators", body: "Everything is text, becoming a number or true/false as needed. Comparisons ignore case; & joins, && joins with a space. Also: + - * / ^ div mod, and, or, not, contains, is, is not. `is a[n] …` tests a type: number, integer, point, rect, logical. `there is a[n] <object>` (or `there is no …`) tests whether a part or card exists. `<point> is within <rect>` tests whether a point (h,v) falls inside a rectangle (left,top,right,bottom).", example: """
                    put "Hyper" & "Talk"          -- HyperTalk
                    put "Hello" && "world"        -- Hello world
                    if "10" > "9" then beep       -- numeric compare
                    if name contains "an" then beep
                    if field "Age" is a number then beep
                    if "10,20" is a point then beep
                    if "per" is in "HyperCard" then beep
                    if there is a field "Notes" then beep
                    if there is no button "Secret" then beep
                    if "10,10" is within "0,0,50,50" then beep
                    """)

                    section("do and value", body: "`do` runs a string as commands, and `the value of` (or value(…)) evaluates a string as an expression — both in the current handler's context, so they see your variables. Handy for building HyperTalk on the fly.", example: """
                    put 10 into n
                    do "put n + 5 into n"           -- n is now 15
                    put the value of "2 + 3 * 4"    -- 14
                    put value("n * 2")              -- 30
                    """)

                    section("Constants and more", body: "empty, space, comma, colon, quote, return, linefeed, formfeed, null, tab, true, false, pi, and the number words zero through ten. `beep` beeps (or `beep 3`). `exit mouseUp` ends a handler early. Comments start with two dashes.", example: """
                    put empty into field "Log"
                    put "a" & comma & space & "b"  -- a, b
                    put ten & colon & zero & zero   -- 10:00
                    put pi                          -- 3.14159265358979
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
