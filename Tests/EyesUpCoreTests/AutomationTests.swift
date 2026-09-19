import Foundation
import Testing
@testable import EyesUpCore

@Suite struct AutomationTests {
    private func parse(_ string: String, cap: TimeInterval? = nil) throws -> AutomationCommand {
        try AutomationParser.parse(#require(URL(string: string)), cap: cap)
    }

    @Test func acceptsTheThreeCommands() throws {
        #expect(try parse("eyesup://start?for=2h") == .start(duration: .finite(7200), display: false))
        #expect(try parse("eyesup://start?for=90m&display=true") == .start(duration: .finite(5400), display: true))
        // "inf" means "as long as a link may ask for", never unbounded (C1).
        #expect(try parse("eyesup://start?for=inf") == .start(duration: .finite(AutomationParser.maxDuration), display: false))
        #expect(try parse("eyesup://start?for=inf", cap: 3600) == .start(duration: .finite(3600), display: false))
        #expect(try parse("eyesup://start?for=INF", cap: 7200) == .start(duration: .finite(7200), display: false))
        #expect(try parse("eyesup://stop") == .stop)
        #expect(try parse("eyesup://extend?by=30m") == .extend(by: 1800))
        #expect(try parse("EYESUP://START?for=1h") == .start(duration: .finite(3600), display: false))
    }

    @Test(arguments: [
        "eyesup://start",                    // missing for=
        "eyesup://start?for=",               // empty
        "eyesup://start?for=25h",            // over the 24h link cap
        "eyesup://start?for=1h&for=2h",      // duplicate key
        "eyesup://start?for=1h&secret=1",    // unexpected key
        "eyesup://start?for=1%20h",          // whitespace
        "eyesup://start?for=%D9%A3h",        // non-ASCII digits
        "eyesup://start?for=1h&display=maybe",
        "eyesup://launch?for=1h",            // unknown command
        "eyesup://stop?all=true",            // stop takes no parameters
        "eyesup://extend",                   // missing by=
        "eyesup://extend?by=inf",            // can't extend by forever
        "https://start?for=1h",              // wrong scheme
        "eyesup://start?for=0m",
        "eyesup://start?for=-1h",
    ])
    func rejectsMalformedLinks(string: String) throws {
        let url = try #require(URL(string: string))
        #expect(throws: (any Error).self) { try AutomationParser.parse(url, cap: nil) }
    }

    @Test func honoursASafetyCapLowerThanTheLinkCap() throws {
        #expect(throws: AutomationError.badParameter) { try parse("eyesup://start?for=6h", cap: 3600) }
        #expect(try parse("eyesup://start?for=30m", cap: 3600) == .start(duration: .finite(1800), display: false))
    }

    // Extra adversarial cases beyond the plan (security review).
    @Test(arguments: [
        "eyesup://start/../../etc/passwd?for=1h",  // path traversal shapes
        "eyesup://start/extra?for=1h",             // any path at all
        "eyesup:start?for=1h",                     // no authority, so no command
        "eyesup://%D1%95top",                      // Cyrillic homoglyph of "stop"
        "eyesup://start?for=1h%00",                // embedded null
        "eyesup://start?for=" + String(repeating: "1", count: 200) + "h",
    ])
    func rejectsAdversarialLinks(string: String) throws {
        let url = try #require(URL(string: string))
        #expect(throws: (any Error).self) { try AutomationParser.parse(url, cap: nil) }
    }

    @Test func acceptsATrailingSlashOnly() throws {
        #expect(try parse("eyesup://stop/") == .stop)
    }
}
