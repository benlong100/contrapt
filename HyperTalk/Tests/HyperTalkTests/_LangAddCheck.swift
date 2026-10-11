import Testing
@testable import HyperTalk

@Test func langAddStackScriptsParse() throws {
    let scripts = [
        "on mouseUp\n  go to previous card\nend mouseUp",
        "on mouseUp\n  go to next card\nend mouseUp",
        "on mouseUp\n  put \"red\" into fruit[\"apple\"]\n  put \"yellow\" into fruit[\"banana\"]\n  put the number of elements of fruit into n\n  put \"The apple is\" && fruit[\"apple\"] & \". There are\" && n && \"fruits.\"\nend mouseUp",
        "on mouseUp\n  put \"Paris\" into w[\"city\"]\n  put 21 into w[\"temp\"]\n  put JSONEncode(w)\nend mouseUp",
        "on mouseUp\n  add 1 to stackData[\"demoClicks\"]\n  put \"You've pressed Try it\" && stackData[\"demoClicks\"] && \"times.\"\nend mouseUp",
        "on mouseUp\n  if the theme of this stack is \"dark\" then\n    set the theme of this stack to \"classic\"\n  else\n    set the theme of this stack to \"dark\"\n  end if\nend mouseUp",
    ]
    for s in scripts { try HyperTalk.check(s) }
}
