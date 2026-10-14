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
    },
    // `url` / `post` / `delete url` ride the player's fetch helper
    // (window.ContraptHttp — honors CORS and the script's timeout). Mirrors
    // how answer/ask bind to window.ContraptDialogs.
    httpRequest: { method, url, body, headers, timeout in
        let global = JSObject.global
        guard let http = global.ContraptHttp.object, let request = http.request.function else {
            return ("", 0, [:], "Networking isn't available here.")
        }
        let headersObject = global.Object.function!.new()
        for (name, value) in headers { headersObject[name] = .string(value) }
        let call = request(this: http, method, url, body ?? JSValue.null, headersObject, timeout)
        guard let promise = JSPromise(from: call),
              let value = try? await promise.value, let reply = value.object else {
            return ("", 0, [:], "The page's network helper failed.")
        }
        var responseHeaders: [String: String] = [:]
        if let headersValue = reply.headers.object,
           let names = global.Object.object?.keys.function?(headersValue).object {
            let count = Int(names.length.number ?? 0)
            for index in 0..<count {
                if let name = names[index].string, let headerValue = headersValue[name].string {
                    responseHeaders[name] = headerValue
                }
            }
        }
        let error = reply.error.isNull ? nil : reply.error.string
        return (reply.body.string ?? "", Int(reply.status.number ?? 0), responseHeaders, error)
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
        // `stackData` persistence: the page seeds window.__STACK_DATA__ from
        // localStorage; `persist` effects flush writes back (player.js).
        let persisted = global.__STACK_DATA__.string ?? ""
        engine = try StackEngine(stackJSON: Data(jsonString.utf8), interaction: interaction,
                                 persistentData: persisted)
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
        // 4th arg: which layer the click hit ("card"/"bkgnd") — disambiguates a
        // scriptID shared by a card and a background part.
        let layer = arguments.count > 3 ? arguments[3].string : nil
        return .string(await engine.dispatchMouseUpJSON(
            partScriptID: Int(arguments.first?.number ?? -1),
            clickLine: line, clickText: text, partLayer: layer
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
    // A `send … in <time>` timer firing (the page's setTimeout):
    // (message, argumentsJSON, partScriptID (-1 = none), cardScriptID).
    api.deliverScheduled = retained(JSClosure.async { arguments in
        .string(await engine.deliverScheduledJSON(
            message: arguments.first?.string ?? "",
            argumentsJSON: arguments.count > 1 ? (arguments[1].string ?? "[]") : "[]",
            partScriptID: arguments.count > 2 ? Int(arguments[2].number ?? -1) : -1,
            cardScriptID: arguments.count > 3 ? Int(arguments[3].number ?? -1) : -1
        ))
    })
    global.ContraptEngine = .object(api)

    // Tell the page the engine is live (boot.js may await this).
    _ = global.__contraptEngineReady.function?()
}

installEngine()
