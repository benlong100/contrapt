//
//  TutorialStack.swift
//  Contrapt
//

import Foundation

/// The built-in tutorial: six cards, each teaching one idea, every script
/// written to be read. HyperCard taught through its sample stacks; this is
/// ours. Created from the launch screen's "Learn HyperTalk" button.
nonisolated extension Stack {
    static func tutorial() -> Stack {
        let backgroundID = UUID()

        func label(_ text: String, x: Double, y: Double, width: Double = 900, height: Double = 60) -> Part {
            Part(
                id: UUID(), name: "Label",
                frame: PartFrame(x: x, y: y, width: width, height: height),
                script: "", kind: .label(LabelPart(text: text))
            )
        }

        func button(_ title: String, name: String, x: Double, y: Double, width: Double = 220, script: String) -> Part {
            Part(
                id: UUID(), name: name,
                frame: PartFrame(x: x, y: y, width: width, height: 56),
                script: script, kind: .button(ButtonPart(title: title))
            )
        }

        func field(_ name: String, placeholder: String, x: Double, y: Double, width: Double = 520) -> Part {
            Part(
                id: UUID(), name: name,
                frame: PartFrame(x: x, y: y, width: width, height: 56),
                script: "", kind: .field(FieldPart(text: "", placeholder: placeholder))
            )
        }

        let background = Background(
            id: backgroundID,
            name: "Tutorial Background",
            script: "",
            parts: [
                button("← Previous", name: "Previous Button", x: 604, y: 688, width: 200, script: """
                on mouseUp
                  go to previous card
                end mouseUp
                """),
                button("Next →", name: "Next Button", x: 824, y: 688, width: 160, script: """
                on mouseUp
                  go to next card
                end mouseUp
                """),
            ]
        )

        let card1 = Card(
            id: UUID(), name: "Welcome", backgroundID: backgroundID,
            script: "", parts: [
                label("Welcome to HyperTalk", x: 64, y: 64),
                label("Every button, field, and card here carries a small script you can read. Tap Edit, then double-tap anything to see how it works — that's the whole idea.", x: 64, y: 140, height: 120),
                label("The Next and Previous buttons below live on the background, so they follow you to every card. Tap Next to begin.", x: 64, y: 280, height: 90),
            ]
        )

        let card2 = Card(
            id: UUID(), name: "Buttons", backgroundID: backgroundID,
            script: "", parts: [
                label("Buttons run handlers", x: 64, y: 64),
                label("A button's script usually answers the mouseUp message — sent when you tap it. This one uses `put` with no destination, which opens the Message Box.", x: 64, y: 140, height: 120),
                button("Say Hello", name: "Hello Button", x: 64, y: 280, script: """
                on mouseUp
                  -- put with no destination goes to the Message Box
                  put "Hello from HyperTalk!"
                end mouseUp
                """),
                label("Try the Message Box yourself: open it from the toolbar and type    2 + 3    or    beep 2", x: 64, y: 370, height: 90),
            ]
        )

        let card3 = Card(
            id: UUID(), name: "Fields", backgroundID: backgroundID,
            script: "", parts: [
                label("Fields hold text", x: 64, y: 64),
                label("Scripts read and write fields by name. Type your name, then tap Greet — and read its script to see if/then/else at work.", x: 64, y: 140, height: 90),
                field("Name", placeholder: "Type your name…", x: 64, y: 250),
                button("Greet", name: "Greet Button", x: 64, y: 330, width: 160, script: """
                on mouseUp
                  if field "Name" is empty then
                    put "Hello, stranger!" into field "Reply"
                  else
                    put "Hello," && field "Name" & "!" into field "Reply"
                  end if
                end mouseUp
                """),
                field("Reply", placeholder: "", x: 64, y: 410),
            ]
        )

        let card4 = Card(
            id: UUID(), name: "Repeat", backgroundID: backgroundID,
            script: "", parts: [
                label("Repeat does the work", x: 64, y: 64),
                label("Loops come in several shapes: repeat 5 times, repeat with i = 1 to 10, repeat while, repeat until, and repeat forever (which the app stops if it runs away).", x: 64, y: 140, height: 120),
                button("Count to 10", name: "Count Button", x: 64, y: 280, script: """
                on mouseUp
                  put empty into field "Counter"
                  repeat with i = 1 to 10
                    put i & space after field "Counter"
                  end repeat
                end mouseUp
                """),
                field("Counter", placeholder: "", x: 64, y: 360),
            ]
        )

        let card5 = Card(
            id: UUID(), name: "The Message Path", backgroundID: backgroundID,
            script: """
            on mouseUp
              -- taps nothing else handles end up here, on the card
              put "The card caught your tap!"
            end mouseUp

            on cheer who
              -- a custom message, sent by the Cheer button below
              put "Hip hip hooray for" && who & "!"
            end cheer
            """, parts: [
                label("Messages travel a path", x: 64, y: 64),
                label("A message goes to the part first, then the card, the background, and the stack — the first handler wins. Tap the empty card background and this card's script answers.", x: 64, y: 140, height: 120),
                button("Cheer", name: "Cheer Button", x: 64, y: 290, width: 160, script: """
                on mouseUp
                  -- cheer isn't built in: it travels the path and
                  -- finds the handler in this card's script
                  cheer "you"
                end mouseUp
                """),
                label("Open the Inspector with nothing selected to read the card's script.", x: 64, y: 380, height: 90),
            ]
        )

        let card6 = Card(
            id: UUID(), name: "Make It Yours", backgroundID: backgroundID,
            script: "", parts: [
                label("Now make something", x: 64, y: 64),
                label("Tap Edit: add buttons, fields, and labels; drag them anywhere; paint on the card; drop in a photo. Everything you build works the way this stack does — readable scripts all the way down.", x: 64, y: 140, height: 120),
                button("Start Over", name: "Start Over Button", x: 64, y: 290, script: """
                on mouseUp
                  beep
                  go to first card
                end mouseUp
                """),
            ]
        )

        return Stack(
            formatVersion: StackFormat.currentVersion,
            id: UUID(),
            name: "Learn HyperTalk",
            cardSize: CardSize(width: 1024, height: 768),
            script: "",
            backgrounds: [background],
            cards: [card1, card2, card3, card4, card5, card6]
        )
    }
}
