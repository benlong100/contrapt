//
//  HyperPadApp.swift
//  HyperPad
//
//  Created by Happy Wanderer on 9/23/26.
//

import SwiftUI

@main
struct HyperPadApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { StackDocument() }) { file in
            ContentView(document: file.document, fileURL: file.fileURL)
        }
        DocumentGroupLaunchScene {
            NewDocumentButton("New Stack")
            NewDocumentButton("Learn HyperTalk", for: StackDocument.self) {
                StackDocument(stack: .tutorial())
            }
        }
    }
}
