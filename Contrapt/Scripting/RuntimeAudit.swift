//
//  RuntimeAudit.swift
//  Contrapt
//
//  Tool #4 (runtime coverage) support, DEBUG-only. Imports a classic stack and
//  runs its `openStack`/`openCard` handlers against a headless
//  DocumentScriptHost, collecting runtime errors that parsing can't catch
//  (unimplemented commands/functions at run time, bad property access, the
//  id-122 class). Lives in the app module because it needs DocumentScriptHost,
//  the HyperTalk runtime, and the importer; driven by the ContraptTests target.
//

#if DEBUG
import Foundation
import SwiftUI
import HyperTalk

@MainActor
enum RuntimeAudit {
    struct Finding: Sendable {
        let stack: String
        let context: String   // "openStack" / "openCard <card>"
        let message: String
    }

    /// Imports the classic stack at `path` and runs its setup handlers,
    /// returning any runtime errors. Runs `openStack` once, then `openCard` on
    /// the first card of each distinct background (each background has its own
    /// openCard script, so this exercises them all without walking 100s of
    /// cards). Each handler runs under a wall-clock timeout so a mouse/idle
    /// poll loop can't hang the sweep.
    static func run(classicStackAt path: String, name: String, timeout: Double = 1.5) async -> [Finding] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return [Finding(stack: name, context: "(read)", message: "could not read file")]
        }
        // Each stack is an independent run — don't carry `start using` state over
        // from a previously-audited stack.
        UsingStackStore.shared.reset()
        // Register sibling stacks (same folder) in the Stack Library so
        // `start using stack "X"` can resolve them, as it would in the app —
        // e.g. H2G2's Hitchhiker's Guide uses "The Library" alongside it.
        let directory = (path as NSString).deletingLastPathComponent
        if let siblings = try? FileManager.default.contentsOfDirectory(atPath: directory) {
            for sibling in siblings where !sibling.hasPrefix(".") {
                StackLibrary.shared.register(url: URL(fileURLWithPath: directory).appendingPathComponent(sibling))
            }
        }
        let stackFork = ResourceFork.forkData(of: URL(fileURLWithPath: path))
        let imported: LegacyStackImporter.Imported
        do {
            imported = try LegacyStackImporter.stack(from: data, name: name, stackFork: stackFork)
        } catch {
            return [Finding(stack: name, context: "(import)", message: "\(error)")]
        }

        var stack = imported.stack
        // Mirror importedContraptFile: record the stack's XCMD/XFCN names so the
        // interpreter no-ops calls to them instead of "Can't understand"
        // (stack(from:) alone doesn't set these).
        if let stackFork {
            stack.externalCommands = ResourceFork.externalNames(from: stackFork).sorted()
        }
        var cardIndex = 0
        let assets = imported.assets
        let host = DocumentScriptHost(
            stack: Binding(get: { stack }, set: { stack = $0 }),
            currentCardIndex: Binding(get: { cardIndex }, set: { cardIndex = $0 }),
            onMessage: { _ in },
            onAnswer: { _, buttons in buttons.first ?? "OK" },
            onAsk: { _, initial in initial },
            onNavigate: { index, _ in cardIndex = index },
            assetData: { assets[$0] }
        )

        var findings: [Finding] = []

        func runHandler(_ message: String, cardAt index: Int, context: String) async {
            cardIndex = index
            let path = scriptPath(stack: stack, cardAt: index)
            if let message = await runBounded(timeout: timeout, {
                _ = try await HyperTalk.send(message, along: path, host: host, maxSteps: 50_000)
            }) {
                findings.append(Finding(stack: name, context: context, message: message))
            }
        }

        await runHandler("openStack", cardAt: 0, context: "openStack")
        // First card of each distinct background.
        var seenBackgrounds = Set<UUID>()
        for (index, card) in stack.cards.enumerated() where seenBackgrounds.insert(card.backgroundID).inserted {
            await runHandler("openCard", cardAt: index, context: "openCard \(card.name)")
        }
        return findings
    }

    /// Fans out every part's `mouseUp` handler and runs it with that part as the
    /// clicked target — the gameplay of a point-and-click stack (the Manhole)
    /// lives in hotspot buttons, which openStack/openCard don't exercise.
    /// Handlers are deduped by script (navigation buttons share one), each runs
    /// under a wall-clock timeout, and the total is capped.
    static func runButtons(classicStackAt path: String, name: String, timeout: Double = 1.0, limit: Int = 1500) async -> [Finding] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return [Finding(stack: name, context: "(read)", message: "could not read file")]
        }
        let stackFork = ResourceFork.forkData(of: URL(fileURLWithPath: path))
        let imported: LegacyStackImporter.Imported
        do { imported = try LegacyStackImporter.stack(from: data, name: name, stackFork: stackFork) }
        catch { return [Finding(stack: name, context: "(import)", message: "\(error)")] }

        var stack = imported.stack
        if let stackFork { stack.externalCommands = ResourceFork.externalNames(from: stackFork).sorted() }
        var cardIndex = 0
        let assets = imported.assets
        let host = DocumentScriptHost(
            stack: Binding(get: { stack }, set: { stack = $0 }),
            currentCardIndex: Binding(get: { cardIndex }, set: { cardIndex = $0 }),
            onMessage: { _ in },
            onAnswer: { _, buttons in buttons.first ?? "OK" },
            onAsk: { _, initial in initial },
            onNavigate: { index, _ in cardIndex = index },
            assetData: { assets[$0] }
        )

        var findings: [Finding] = []
        var seenScripts = Set<String>()
        var dispatched = 0

        func runPart(_ part: Part, domain: HyperTalkObject.PartDomain, cardAt index: Int, context: String) async {
            guard part.script.lowercased().contains("on mouseup") else { return }
            guard seenScripts.insert(part.script).inserted else { return } // dedupe shared scripts
            guard dispatched < limit else { return }
            dispatched += 1
            cardIndex = index
            let partLayer = ScriptLayer(
                name: "\(part.kind.word) \"\(part.name)\" script", source: part.script,
                object: .part(kind: part.kind.word, domain: domain,
                              reference: .id(String(part.scriptID)), onCard: nil))
            let layers = [partLayer] + scriptPath(stack: stack, cardAt: index)
            if let message = await runBounded(timeout: timeout, {
                _ = try await HyperTalk.send("mouseUp", along: layers, host: host, maxSteps: 50_000)
            }) {
                findings.append(Finding(stack: name, context: context, message: message))
            }
        }

        var seenBackgrounds = Set<UUID>()
        for (index, card) in stack.cards.enumerated() {
            if dispatched >= limit { break }
            for part in card.parts {
                await runPart(part, domain: .card, cardAt: index, context: "cd \"\(card.name)\" › \(part.name)")
            }
            if seenBackgrounds.insert(card.backgroundID).inserted,
               let background = stack.backgrounds.first(where: { $0.id == card.backgroundID }) {
                for part in background.parts {
                    await runPart(part, domain: .background, cardAt: index, context: "bg \"\(background.name)\" › \(part.name)")
                }
            }
        }
        if dispatched >= limit {
            findings.append(Finding(stack: name, context: "(capped)", message: "stopped after \(limit) unique button handlers"))
        }
        return findings
    }

    /// Runs `op` but gives up after `timeout` seconds. Returns nil on clean
    /// completion, else the error message (or "timed out (poll loop?)"). The
    /// timeout cancels `op`, unwinding a `wait`-based poll loop via its
    /// cancellable sleep.
    private static func runBounded(timeout: Double, _ op: @escaping @Sendable () async throws -> Void) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask {
                do { try await op(); return nil }
                catch let e as ScriptError { return e.message }
                catch is CancellationError { return "timed out (poll loop?)" }
                catch { return "\(error)" }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return "timed out (poll loop?)"
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    /// The card/background/stack script layers for a card — the dispatch path
    /// `openCard`/`openStack` travels. Mirrors ContentView.scriptPath (which is
    /// private) for the no-part case.
    private static func scriptPath(stack: Stack, cardAt index: Int) -> [ScriptLayer] {
        guard stack.cards.indices.contains(index) else { return [] }
        let card = stack.cards[index]
        var layers: [ScriptLayer] = [
            ScriptLayer(name: "card \"\(card.name)\" script", source: card.script, object: .thisCard)
        ]
        if let background = stack.backgrounds.first(where: { $0.id == card.backgroundID }) {
            layers.append(ScriptLayer(name: "background script", source: background.script, object: .thisBackground))
        }
        layers.append(ScriptLayer(name: "stack script", source: stack.script, object: .thisStack))
        return layers
    }
}
#endif
