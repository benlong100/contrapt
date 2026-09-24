//
//  ContraptApp.swift
//  Contrapt
//
//  Created by Happy Wanderer on 9/23/26.
//

import SwiftUI

@main
struct ContraptApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { StackDocument() }) { file in
            ContentView(document: file.document, fileURL: file.fileURL)
                #if os(macOS)
                .frame(minWidth: 900, minHeight: 640)
                #endif
        }
        #if os(macOS)
        // Open new document windows large enough to show a whole card
        // comfortably with room for the inspector.
        .defaultSize(width: 1280, height: 900)
        #endif
        // The launch scene's New/Learn buttons are an iOS-only feature;
        // macOS gets New and Open from the standard File menu. (A Help-menu
        // entry point for the tutorial is a natural macOS follow-up.)
        #if os(iOS)
        DocumentGroupLaunchScene {
            NewDocumentButton("New Stack")
            NewDocumentButton("Learn HyperTalk", for: StackDocument.self) {
                StackDocument(stack: .tutorial())
            }
        }
        #endif
    }
}
