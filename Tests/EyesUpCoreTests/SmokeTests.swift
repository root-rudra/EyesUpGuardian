import Testing
@testable import EyesUpCore

@Test func versionIsSemantic() {
    #expect(EyesUpCore.version.split(separator: ".").count == 3)
}
