import Testing

@testable import Tickoff

struct ProjectColourTests {
    @Test func keysAreTheStringsAlreadyStoredInTheDatabase() {
        #expect(
            ProjectColour.allCases.map(\.key) == [
                "system", "indigo", "violet", "teal", "rose", "orange",
            ])
    }

    @Test func everyStoredKeyMapsBackToItsColour() {
        for colour in ProjectColour.allCases { #expect(ProjectColour(key: colour.key) == colour) }
    }

    @Test func anUnknownKeyIsNotAColour() {
        #expect(ProjectColour(key: "chartreuse") == nil)
    }

    @Test func labelsAreTheUserFacingNames() {
        #expect(
            ProjectColour.allCases.map(\.label) == [
                "Accent", "Indigo", "Purple", "Teal", "Pink", "Orange",
            ])
    }
}
