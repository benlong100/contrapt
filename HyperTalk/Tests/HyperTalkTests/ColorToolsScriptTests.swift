//
//  ColorToolsScriptTests.swift
//  HyperTalk
//
//  Walls from Apple's Color Tools stack (the AddColor coloring tools) — a
//  menus/windows/XCMD-heavy fixture. It exercises constructs Contrapt doesn't
//  model (palette windows, custom menus, externals), which must all parse and
//  degrade gracefully so old stacks import.
//

import Foundation
import Testing
@testable import HyperTalk

@Test func menuItemCountReadsZero() async throws {
    // `the number of menuItems of menu "File"` — Contrapt has no menus, so
    // the count is 0 and the classic disable-every-item loop never runs.
    let host = MockHost(fields: ["out": ""])
    try await run("""
    on mouseUp
      put the number of menuItems of menu "File" into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "0")
}

@Test func menuItemCountDrivesARepeatToZeroIterations() async throws {
    // The Color Tools AC_start line that walled, verbatim shape:
    // `repeat with x = 1 to (the number of menuItems of menu "File")-1`.
    let host = MockHost(fields: ["out": "untouched"])
    try await run("""
    on mouseUp
      repeat with x = 1 to (the number of menuItems of menu "File")-1
        put "ran" into field "out"
      end repeat
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "untouched")
}

@Test func numberOfMenusReadsZero() async throws {
    let host = MockHost(fields: ["out": ""])
    try await run("""
    on mouseUp
      put the number of menus into field "out"
    end mouseUp
    """, host: host)
    #expect(host.fields["out"] == "0")
}

@Test func colorToolsStartHandlerParses() async throws {
    // A condensed AC_start: the window save/restore, the menu-count loop, the
    // qualified `card window` reads, and `set … of window …` — every construct
    // that walled during import, in one handler.
    let script = """
    on AC_start
      global AC_Wins,AC_Palminder
      put the visible of window "Tools"&","&¬
      the visible of window "Message Watcher" into AC_Wins
      hide window "Message Watcher"
      if there is not a window "AddColor" then
        if there is a menu "File" then
          repeat with x = 1 to (the number of menuItems of menu "File")-1
            disable menuItem x of menu "File"
          end repeat
        end if
        put the top of card window into y1
        put the left of card window into x1
        set the loc of window "AddColor" to AC_Palminder
        show window "AddColor"
      else
        beep
      end if
    end AC_start
    """
    _ = try Parser.parse(script)
}
