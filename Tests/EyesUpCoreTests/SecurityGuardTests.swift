import Foundation
import Testing

/// Spec §9: app code must never run commands, open network connections, escalate privileges, or add dependencies.
@Suite struct SecurityGuardTests {
    static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // EyesUpCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // package root

    /// Rules that only make sense in code: user-facing copy may say "sudo", code may not call it.
    static let codeOnlyPatterns: Set<String> = [#"\bsudo\b"#]

    static let forbidden: [(pattern: String, reason: String)] = [
        (#"\bProcess\s*\("#, "launching processes"),
        (#"\bNSTask\b"#, "launching processes"),
        (#"\bposix_spawn"#, "launching processes"),
        (#"\bpopen\s*\("#, "launching processes"),
        // C system(), bare or module-qualified; not SwiftUI's `.system(size:)` font.
        (#"(?:^|[^.\w]|Darwin\.|Glibc\.)system\s*\("#, "launching processes"),
        (#"\bexec(l|lp|le|v|vp|ve)\s*\("#, "launching processes"),
        (#"NSAppleScript|OSAScript"#, "running scripts"),
        (#"\bURLSession\b"#, "network access"),
        (#"\bNWConnection\b|\bNWListener\b|import\s+Network\b"#, "network access"),
        (#"\bsocket\s*\("#, "network access"),
        (#"AuthorizationExecuteWithPrivileges|AuthorizationCreate|SMJobBless"#, "privilege escalation"),
        (#"\bsudo\b"#, "privilege escalation"),
    ]

    /// Text with double-quoted string literals blanked out, so copy can't trip a code-only rule.
    static func withoutStringLiterals(_ text: String) throws -> String {
        text.replacing(try Regex(#""(?:[^"\\\n]|\\.)*""#), with: "\"\"")
    }

    static func violations(in text: String) throws -> [String] {
        let code = try withoutStringLiterals(text)
        return try forbidden.compactMap { rule in
            // Simple word boundaries: Unicode boundaries treat "URLSession.shared" as one word and would miss it.
            let haystack = codeOnlyPatterns.contains(rule.pattern) ? code : text
            return try haystack.firstMatch(of: Regex(rule.pattern).wordBoundaryKind(.simple)) == nil ? nil : rule.reason
        }
    }

    @Test func guardDetectsViolations() throws {
        #expect(try Self.violations(in: "let p = Process()") == ["launching processes"])
        #expect(try Self.violations(in: "URLSession.shared") == ["network access"])
        #expect(try Self.violations(in: "let id = ProcessIdentity(pid: 1, startTime: 2)").isEmpty)
        #expect(try Self.violations(in: ".font(.system(size: 34))").isEmpty)
        #expect(try Self.violations(in: "system(\"ls\")") == ["launching processes"])
        #expect(try Self.violations(in: "_ = Darwin.system(cmd)") == ["launching processes"])
        // User-facing copy may mention sudo; only code may not.
        #expect(try Self.violations(in: #"Text("commands run with sudo can\'t be matched")"#).isEmpty)
        #expect(try Self.violations(in: "let helper = sudo").isEmpty == false)
    }

    @Test func sourcesContainNoForbiddenAPIs() throws {
        let sources = Self.packageRoot.appendingPathComponent("Sources")
        let enumerator = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty)
        for file in files {
            let found = try Self.violations(in: String(contentsOf: file, encoding: .utf8))
            #expect(found.isEmpty, "\(file.lastPathComponent) uses a forbidden API: \(found)")
        }
    }

    @Test func packageHasNoDependencies() throws {
        let manifest = try String(contentsOf: Self.packageRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
        #expect(!manifest.contains(".package("))
    }
}
