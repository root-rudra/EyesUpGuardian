import Foundation
import Testing

/// Spec §9: app code must never run commands, open network connections, escalate privileges, or add dependencies.
@Suite struct SecurityGuardTests {
    static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // EyesUpCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // package root

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

    static func violations(in text: String) throws -> [String] {
        try forbidden.compactMap { rule in
            // Simple word boundaries: Unicode boundaries treat "URLSession.shared" as one word and would miss it.
            try text.firstMatch(of: Regex(rule.pattern).wordBoundaryKind(.simple)) == nil ? nil : rule.reason
        }
    }

    @Test func guardDetectsViolations() throws {
        #expect(try Self.violations(in: "let p = Process()") == ["launching processes"])
        #expect(try Self.violations(in: "URLSession.shared") == ["network access"])
        #expect(try Self.violations(in: "let id = ProcessIdentity(pid: 1, startTime: 2)").isEmpty)
        #expect(try Self.violations(in: ".font(.system(size: 34))").isEmpty)
        #expect(try Self.violations(in: "system(\"ls\")") == ["launching processes"])
        #expect(try Self.violations(in: "_ = Darwin.system(cmd)") == ["launching processes"])
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
