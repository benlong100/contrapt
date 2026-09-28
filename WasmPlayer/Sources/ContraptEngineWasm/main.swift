//
//  main.swift
//  ContraptEngineWasm
//
//  The Wasm entry point for exported websites. Reads the stack the page
//  already loaded (window.__STACK__, from stack-data.js), builds a StackEngine,
//  and installs `window.ContraptEngine` — the async, JSON-string API that
//  player.js upgrades itself with:
//
//      snapshot()          -> { name, cardCount, currentCardIndex, …, state }
//      start()             -> { effects, state }        (openStack + openCard)
//      mouseUp(scriptID)   -> { effects, state } | { error }
//      openCard(index)     -> { effects, state } | { error }
//      message(line)       -> { result, effects, state } | { error }
//
//  Interactive commands (`answer`, `ask`, `wait`) call window.ContraptDialogs
//  when the page provides it (methods may return promises), else fall back to
//  instant defaults so scripts never hang.
//

import Foundation
import HyperTalkEngine
import JavaScriptKit
import JavaScriptEventLoop

// Route Swift concurrency through the browser's event loop — this is what
// lets the async interpreter run to completion between JS events.
JavaScriptEventLoop.installGlobalExecutor()

/// Closures handed to JS must outlive this main function.
var retainedClosures: [JSClosure] = []

/// Calls an optional page-supplied dialog helper, awaiting a promise if the
/// helper returns one. Nil when the page provides no such helper.
func callDialog(_ name: String, _ arguments: [ConvertibleToJSValue]) async -> JSValue? {
    let dialogs = JSObject.global.ContraptDialogs
    guard let owner = dialogs.object, let function = owner[name].function else { return nil }
    let result = function(this: owner, arguments: arguments.map { $0.jsValue() })
    if let promise = JSPromise(from: result) {
        return try? await promise.value
    }
    return result
}

let interaction = EngineInteraction(
    answer: { prompt, buttons in
        if let value = await callDialog("answer", [prompt, buttons]), let choice = value.string {
            return choice
        }
        // No dialog helper: HyperCard's default button is the last one.
        return buttons.last ?? "OK"
    },
    ask: { prompt, initialAnswer in
        if let value = await callDialog("ask", [prompt, initialAnswer]) {
            return value.isNull ? nil : value.string
        }
        // window.prompt is synchronous but that's fine across the boundary.
        if let promptFunction = JSObject.global.prompt.function {
            let result = promptFunction(prompt, initialAnswer)
            return result.isNull ? nil : result.string
        }
        return initialAnswer
    },
    wait: { seconds in
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let timer = JSOneshotClosure { _ in
                continuation.resume()
                return .undefined
            }
            _ = JSObject.global.setTimeout.function?(timer, seconds * 1000)
        }
    }
)

func installEngine() {
    let global = JSObject.global

    // The page defines window.__STACK__ (an object; stack-data.js). The JSON
    // string is the seam — stringify it back rather than marshalling structure.
    let stackValue = global.__STACK__
    let jsonString: String?
    if let text = stackValue.string {
        jsonString = text
    } else if stackValue.object != nil {
        jsonString = global.JSON.object?.stringify.function?(stackValue).string
    } else {
        jsonString = nil
    }
    guard let jsonString else {
        _ = global.console.object?.error.function?("ContraptEngine: window.__STACK__ is missing; staying static.")
        return
    }

    let engine: StackEngine
    do {
        engine = try StackEngine(stackJSON: Data(jsonString.utf8), interaction: interaction)
    } catch {
        _ = global.console.object?.error.function?("ContraptEngine: couldn't load the stack: \(error)")
        return
    }

    func retained(_ closure: JSClosure) -> JSValue {
        retainedClosures.append(closure)
        return .object(closure)
    }

    let api = JSObject.global.Object.function!.new()
    api.snapshot = retained(JSClosure { _ in
        .string(engine.snapshotJSON())
    })
    api.start = retained(JSClosure.async { _ in
        .string(await engine.startJSON())
    })
    api.mouseUp = retained(JSClosure.async { arguments in
        let line = arguments.count > 1 ? arguments[1].number.map { Int($0) } : nil
        let text = arguments.count > 2 ? arguments[2].string : nil
        return .string(await engine.dispatchMouseUpJSON(
            partScriptID: Int(arguments.first?.number ?? -1),
            clickLine: line, clickText: text
        ))
    })
    api.openCard = retained(JSClosure.async { arguments in
        .string(await engine.openCardJSON(index: Int(arguments.first?.number ?? 0)))
    })
    api.message = retained(JSClosure.async { arguments in
        .string(await engine.runMessageJSON(arguments.first?.string ?? ""))
    })
    api.sendToPart = retained(JSClosure.async { arguments in
        .string(await engine.sendToPartJSON(
            arguments.first?.string ?? "",
            partScriptID: arguments.count > 1 ? Int(arguments[1].number ?? -1) : -1
        ))
    })
    api.setField = retained(JSClosure { arguments in
        .string(engine.setFieldJSON(
            partScriptID: Int(arguments.first?.number ?? -1),
            text: arguments.count > 1 ? (arguments[1].string ?? "") : ""
        ))
    })
    global.ContraptEngine = .object(api)

    // Tell the page the engine is live (boot.js may await this).
    _ = global.__contraptEngineReady.function?()
}

installEngine()
