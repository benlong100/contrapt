//
//  ReindentTests.swift
//  HyperTalk
//

import Foundation
import Testing
@testable import HyperTalk

@Test func reindentsNestedBlocks() async {
    let messy = """
    on mouseUp
    repeat with i = 1 to 10
    if i mod 3 = 0 then
    put "fizz" after field "Log"
    else
    put i after field "Log"
    end if
    end repeat
    end mouseUp
    """
    let expected = """
    on mouseUp
      repeat with i = 1 to 10
        if i mod 3 = 0 then
          put "fizz" after field "Log"
        else
          put i after field "Log"
        end if
      end repeat
    end mouseUp
    """
    #expect(HyperTalk.reindent(messy) == expected)
}

@Test func elseIfChainsAlignWithTheirIf() async {
    let messy = """
    on mouseUp
    if x = 1 then
    put "one"
    else if x = 2 then
    put "two"
    else
    put "many"
    end if
    end mouseUp
    """
    let expected = """
    on mouseUp
      if x = 1 then
        put "one"
      else if x = 2 then
        put "two"
      else
        put "many"
      end if
    end mouseUp
    """
    #expect(HyperTalk.reindent(messy) == expected)
}

@Test func singleLineIfDoesNotIndent() async {
    let source = """
    on mouseUp
      if x = 1 then put "one"
      put "after"
    end mouseUp
    """
    #expect(HyperTalk.reindent(source) == source)
}

@Test func elseAfterSingleLineIfStaysPut() async {
    let source = """
    on mouseUp
      if x = 1 then put "one"
      else put "other"
      put "after"
    end mouseUp
    """
    #expect(HyperTalk.reindent(source) == source)
}

@Test func keywordsInsideStringsAndCommentsAreIgnored() async {
    let source = """
    on mouseUp
      put "if then repeat" into x -- repeat forever
      put "done" into y
    end mouseUp
    """
    #expect(HyperTalk.reindent(source) == source)
}

@Test func multipleHandlersEachStartAtZero() async {
    let messy = """
    on mouseUp
    go to next card
    end mouseUp

    on openCard
    put "hi"
    end openCard
    """
    let expected = """
    on mouseUp
      go to next card
    end mouseUp

    on openCard
      put "hi"
    end openCard
    """
    #expect(HyperTalk.reindent(messy) == expected)
}

@Test func unbalancedEndsClampAtZero() async {
    let source = """
    end repeat
    end if
    put "still here"
    """
    let result = HyperTalk.reindent(source)
    #expect(result.hasPrefix("end repeat"))
    #expect(result.contains("\nput \"still here\""))
}

@Test func incompleteCodeIsHandledGently() async {
    // Mid-typing states must not crash or misbehave badly.
    _ = HyperTalk.reindent("on mouseUp\n  if x = 1 then\n    put \"unterminated")
    _ = HyperTalk.reindent("repeat")
    _ = HyperTalk.reindent("")
}

@Test func caretLineGetsBlockDepthIndentationWhenRequested() async {
    let source = "on mouseUp\n  put 1\n\nend mouseUp"
    let result = HyperTalk.reindent(source, indentingEmptyLine: 2)
    #expect(result == "on mouseUp\n  put 1\n  \nend mouseUp")
}

@Test func caretLineInsideNestedBlocksIndentsDeeper() async {
    let source = "on mouseUp\n  repeat 3 times\n\n  end repeat\nend mouseUp"
    let result = HyperTalk.reindent(source, indentingEmptyLine: 2)
    #expect(result == "on mouseUp\n  repeat 3 times\n    \n  end repeat\nend mouseUp")
}

@Test func otherBlankLinesStayEmpty() async {
    let source = "on mouseUp\n\n  put 1\n\nend mouseUp"
    let result = HyperTalk.reindent(source, indentingEmptyLine: 3)
    #expect(result == "on mouseUp\n\n  put 1\n  \nend mouseUp")
}
