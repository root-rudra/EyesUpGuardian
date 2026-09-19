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
        (#"\bProcess\.(launchedProcess|launchedTaskWithLaunchPath)"#, "launching processes"),
        (#"\b(v?fork|execvP|posix_spawnp)\s*\("#, "launching processes"),
        (#"NSWorkspace[^\n]{0,40}\.(open|openApplication|launchApplication|openURLs)\s*\("#, "launching other apps"),
        (#"\bdl(open|sym)\s*\("#, "loading code at runtime"),
        (#"\b(getaddrinfo|CFSocket|NSURLConnection|NWPathMonitor)\b"#, "network access"),
        (#"\bset(res|re|r|e)?[ug]id\b|\b(SMAppService|SMLoginItemSetEnabled)\b"#, "privilege escalation"),
        (#"NSXPCConnection\s*\([^)\n]*machServiceName"#, "privilege escalation"),
        (#"\bProcess(\s*\(|\.init\b|\.launchedProcess|\.launchedTaskWithLaunchPath)"#, "launching processes"),
        (#":\s*Process\s*=\s*\.init\b"#, "launching processes"),
        (#"\b\w*exec(v|l)[ep]{0,2}\s*\("#, "launching processes"),
        (#"\.(openApplication|launchApplication|openURLs)\s*\(|\bLSOpenCFURLRef\s*\("#, "launching other apps"),
        (#"\b(ws|workspace|NSWorkspace\.shared)\.open\s*\("#, "launching other apps"),
        (#"\bBundle\s*\([^)\n]*\)\??\.load\s*\(|\bobjc_getClass\s*\(|dyld_dynamic_interpose"#, "loading code at runtime"),
        (#"\bURLRequest\s*\(|CFStreamCreatePairWithSocketToHost|\b(connect|getaddrinfo)\s*\("#, "network access"),
        (#"NSAppleEventDescriptor\s*\([^)\n]*eventClass"#, "running scripts"),
    ]

    /// Text with double-quoted string literals blanked out, so copy can't trip a code-only rule.
    static func withoutStringLiterals(_ text: String) throws -> String {
        text.replacing(try Regex(#""(?:[^"\\\n]|\\.)*""#), with: "\"\"")
    }

    /// Each reason once, in rule order: several patterns can describe the same call.
    static func violations(in text: String) throws -> [String] {
        let code = try withoutStringLiterals(text)
        var reasons: [String] = []
        for reason in try matchedReasons(text: text, code: code) where !reasons.contains(reason) {
            reasons.append(reason)
        }
        return reasons
    }

    private static func matchedReasons(text: String, code: String) throws -> [String] {
        try forbidden.compactMap { rule in
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
        // Spellings the first version of this guard missed.
        #expect(try Self.violations(in: "Process.launchedProcess(launchPath: p, arguments: [])") == ["launching processes"])
        #expect(try Self.violations(in: "let pid = fork()") == ["launching processes"])
        #expect(try Self.violations(in: "NSWorkspace.shared.launchApplication(app)") == ["launching other apps"])
        #expect(try Self.violations(in: "NSWorkspace.shared.open(url)") == ["launching other apps"])
        #expect(try Self.violations(in: "let handle = dlopen(path, RTLD_NOW)") == ["loading code at runtime"])
        #expect(try Self.violations(in: "getaddrinfo(host, nil, &hints, &result)") == ["network access"])
        #expect(try Self.violations(in: "seteuid(0)") == ["privilege escalation"])
        #expect(try Self.violations(in: "SMAppService.daemon(plistName: p)") == ["privilege escalation"])
        #expect(try Self.violations(in: "let p = Process.init()") == ["launching processes"])
        #expect(try Self.violations(in: "var p: Process = .init()") == ["launching processes"])
        #expect(try Self.violations(in: "fexecve(fd, argv, envp)") == ["launching processes"])
        #expect(try Self.violations(in: "workspace.openApplication(at: url, configuration: c)") == ["launching other apps"])
        #expect(try Self.violations(in: "ws.open(url)") == ["launching other apps"])
        #expect(try Self.violations(in: "setreuid(0, 0)") == ["privilege escalation"])
        #expect(try Self.violations(in: "SMLoginItemSetEnabled(id, true)") == ["privilege escalation"])
        #expect(try Self.violations(in: "NSXPCConnection(machServiceName: n, options: .privileged)") == ["privilege escalation"])
        #expect(try Self.violations(in: "Bundle(path: p)?.load()") == ["loading code at runtime"])
        // Naming NSTask at all is worth flagging, so this trips two rules.
        #expect(try Self.violations(in: "objc_getClass(\"NSTask\")") == ["launching processes", "loading code at runtime"])
        #expect(try Self.violations(in: "var request = URLRequest(url: u)") == ["network access"])
        #expect(try Self.violations(in: "connect(fd, addr, len)") == ["network access"])
        #expect(try Self.violations(in: "NSAppleEventDescriptor(eventClass: c, eventID: i, targetDescriptor: t, returnID: r, transactionID: x)") == ["running scripts"])
        // Legitimate code must stay clean.
        #expect(try Self.violations(in: "let data = try Data(contentsOf: url)").isEmpty)
        #expect(try Self.violations(in: "popover.show(relativeTo: r, of: v, preferredEdge: .minY)").isEmpty)
        #expect(try Self.violations(in: "NSWorkspace.shared.runningApplications").isEmpty)
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
