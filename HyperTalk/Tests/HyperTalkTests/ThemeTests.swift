//
//  ThemeTests.swift
//  HyperTalk
//
//  The built-in theme catalog (ThemeSpec) — name resolution, aliases, and the
//  Classic-is-a-no-op invariant. The app and web renderers both consume this,
//  so getting the resolution right here protects both.
//

import Testing
@testable import HyperTalk

@Test func themeResolvesCanonicalNames() {
    #expect(ThemeSpec.named("classic").name == "classic")
    #expect(ThemeSpec.named("light").name == "light")
    #expect(ThemeSpec.named("dark").name == "dark")
}

@Test func themeResolutionIsCaseAndWhitespaceInsensitive() {
    #expect(ThemeSpec.named("Dark").name == "dark")
    #expect(ThemeSpec.named("  DARK  ").name == "dark")
    #expect(ThemeSpec.named("Modern Light").name == "light")
}

@Test func themeAliasesMapToModernThemes() {
    #expect(ThemeSpec.named("modern").name == "light")
    #expect(ThemeSpec.named("modern light").name == "light")
    #expect(ThemeSpec.named("modern dark").name == "dark")
}

@Test func unknownOrEmptyThemeFallsBackToClassic() {
    #expect(ThemeSpec.named(nil).name == "classic")
    #expect(ThemeSpec.named("").name == "classic")
    #expect(ThemeSpec.named("bogus").name == "classic")
}

@Test func classicFollowsSystemAndModernThemesDoNot() {
    #expect(ThemeSpec.classic.followsSystem == true)
    #expect(ThemeSpec.light.followsSystem == false)
    #expect(ThemeSpec.dark.followsSystem == false)
}

@Test func canonicalNameNormalizes() {
    #expect(ThemeSpec.canonicalName("Dark") == "dark")
    #expect(ThemeSpec.canonicalName("whatever") == "classic")
}

@Test func catalogIsClassicLightDarkInOrder() {
    #expect(ThemeSpec.all.map(\.name) == ["classic", "light", "dark"])
}
