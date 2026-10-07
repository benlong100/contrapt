//
//  OracleDiffTests.swift
//  Env-gated evaluator for the Basilisk real-HyperCard oracle diff
//  (Scripts/oracle-diff.sh). Reads one HyperTalk expression per line from
//  CONTRAPT_ORACLE_IN, evaluates each in Contrapt's interpreter, and writes
//  one answer per line to CONTRAPT_ORACLE_OUT ("ERROR: …" on a throw).
//  Inert in a normal `swift test` run (no env → skips).
//

import Foundation
import Testing
@testable import HyperTalk

@Test func oracleEvaluateExpressions() async throws {
    guard let inPath = ProcessInfo.processInfo.environment["CONTRAPT_ORACLE_IN"],
          let outPath = ProcessInfo.processInfo.environment["CONTRAPT_ORACLE_OUT"] else { return }
    let expressions = try String(contentsOfFile: inPath, encoding: .utf8)
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map(String.init)
    var answers: [String] = []
    for expression in expressions {
        let trimmed = expression.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { answers.append(""); continue }
        do {
            // Mirror the guest Probe stack's card field "pf" (probe v4) so
            // field-context lines compare like for like.
            // (MockHost keys card-domain fields as "card <name>"; corpus
            // field lines must therefore say `card field`/`cd fld`.)
            let host = MockHost(fields: ["card pf": ""])
            // "@stmt | stmt | …" runs statements that set probeResult (the
            // probe stack's v3 protocol); a bare line is an expression.
            let body: String
            if trimmed.hasPrefix("@") {
                let statements = trimmed.dropFirst()
                    .split(separator: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .joined(separator: "\n")
                body = "\(statements)\nput probeResult"
            } else {
                body = "put (\(trimmed)) into probeResult\nput probeResult"
            }
            try await HyperTalk.run(handler: "probe",
                                    in: "on probe\n\(body)\nend probe",
                                    host: host, maxSteps: 100_000)
            // `put` with no destination lands in the host message box; a
            // multi-line value flattens so output stays line-per-expression.
            let answer = (host.messages.last ?? "")
                .replacingOccurrences(of: "\n", with: "\u{2029}")
            answers.append(answer)
        } catch {
            answers.append("ERROR: \(error.localizedDescription)")
        }
    }
    try answers.joined(separator: "\n").appending("\n")
        .write(toFile: outPath, atomically: true, encoding: .utf8)
}
