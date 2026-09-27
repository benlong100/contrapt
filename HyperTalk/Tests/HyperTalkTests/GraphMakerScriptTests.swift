//
//  GraphMakerScriptTests.swift
//  HyperTalk
//
//  Apple's Graph Maker 2.3 stack script (1987-1995) — a wall-driven fixture:
//  the whole script must parse for any handler to run.
//

import Foundation
import Testing
@testable import HyperTalk

private let graphMakerStackScript = """
on openStack
  -- Requires handler: wrongStack
  if wrongStack() then pass openStack -- in case stackInUse
  global IsCommonData,theData,SavLvl
  put the userLevel into SavLvl
  set the userLevel to 5
  if there is a bg "Graphs" then
    set hilite of bg btn id 68 of cd 1 of bg "Graphs" to false -- shared data
  end if
  put false into IsCommonData
  put empty into theData
  pass openStack
end openStack

on closeStack
  -- Requires handler: resetDataInfo,wrongStack
  if wrongStack() then pass closeStack -- in case stackInUse
  global IsCommonData,SavLvl
  resetDataInfo
  put empty into IsCommonData
  if SavLvl is a number then set the userLevel to SavLvl
  pass closeStack
end closeStack

function wrongStack
  get the value of word 2 of the long name of me
  return (it is not line 1 of the stacks)
end wrongStack

on goToCard whichCard
  get bg field "Graph Rect" of card whichCard
  set rect of bg btn "Frame" of card whichCard to line 1 of it
  set rect of bg btn "Grow" of card whichCard to line 2 of it
  visual effect shrink to top slow
  go to card whichCard
  wait while the mouseClick -- prevents redraw if user double clicked
end goToCard

on goCard
  go to card (the short name of the target) of this bkgnd
end goCard

on resetDataInfo
  global theData,theLabels,theTitle,theDataTitle,theUnits
  put empty into theData
  put empty into theLabels
  put empty into theTitle
  put empty into theDataTitle
  put empty into theUnits
end resetDataInfo
"""

@Test func graphMakerStackScriptParses() throws {
    _ = try Parser.parse(graphMakerStackScript)
}
