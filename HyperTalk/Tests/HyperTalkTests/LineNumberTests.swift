//
//  LineNumberTests.swift
//  Error line numbers must match what an editor shows — comments, blank
//  lines, ¬ continuations (incl. inside comments/strings), trailing
//  comments, and block statements must not shift the count.
//

import Foundation
import Testing
@testable import HyperTalk

@Test func errorLineSurvivesCommentsBlanksAndContinuations() async throws {
    var lines: [String] = []
    lines.append("on probe")                        // 1
    lines.append("  -- a comment line")             // 2
    lines.append("")                                // 3
    lines.append("  put 1 into x -- trailing")      // 4
    lines.append("  if x = 1 then")                 // 5
    lines.append("    put 2 into ¬")                // 6
    lines.append("      y")                         // 7
    lines.append("  else")                          // 8
    lines.append("    put 3 into y")                // 9
    lines.append("  end if")                        // 10
    lines.append("  repeat with i = 1 to 2")        // 11
    lines.append("    add 1 to x")                  // 12
    lines.append("  end repeat")                    // 13
    lines.append("")                                // 14
    lines.append("  -- another comment")            // 15
    lines.append("  put \"a\" + 1 into z")          // 16: the runtime error
    lines.append("end probe")                       // 17
    do {
        _ = try await HyperTalk.run(handler: "probe", in: lines.joined(separator: "\n"), host: MockHost(), maxSteps: 1000)
        Issue.record("expected a runtime error")
    } catch let error as ScriptError {
        #expect(error.line == 16)
    }
}

@Test func tokenizerCountsLinesThroughEveryContinuationForm() throws {
    // reported last-token line == actual text lines, for the patterns that
    // could plausibly lose count.
    let samples: [String] = [
        "on a\nput 1\nend a",
        "on a\nput \"x\" -- trailing ¬ in comment\nput 2\nend a",
        "on a\nput \"literal ¬ inside string\"\nput 2\nend a",
        "on a\nput 1 ¬\n ¬\n into x\nend a",
        "on a -- comment with ¬ at end ¬\nput 1\nend a",
    ]
    for sample in samples {
        let tokens = (try? Tokenizer.tokenize(sample)) ?? []
        #expect(tokens.last?.line == sample.components(separatedBy: "\n").count,
                "line drift in: \(sample.prefix(40))")
    }
}
