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
        // SMAppService.mainApp is just "open me at login"; the daemon/agent/loginItem forms install
        // something that runs on its own, which this app never does.
        (#"\bset(res|re|r|e)?[ug]id\b|SMAppService\.(daemon|agent|loginItem)\s*\(|\bSMLoginItemSetEnabled\b"#, "privilege escalation"),
        (#"NSXPCConnection\s*\([^)\n]*machServiceName"#, "privilege escalation"),
        (#"\bProcess(\s*\(|\.init\b|\.launchedProcess|\.launchedTaskWithLaunchPath)"#, "launching processes"),
        (#":\s*Process\s*=\s*\.init\b"#, "launching processes"),
        (#"\b\w*exec(v|l)[ep]{0,2}\s*\("#, "launching processes"),
        (#"\.(openApplication|launchApplication|openURLs)\s*\(|\bLSOpenCFURLRef\s*\("#, "launching other apps"),
        (#"\b(ws|workspace|NSWorkspace\.shared)\.open\s*\("#, "launching other apps"),
        (#"\bBundle\s*\([^)\n]*\)\??\.load\s*\(|\bobjc_getClass\s*\(|dyld_dynamic_interpose"#, "loading code at runtime"),
        (#"\bURLRequest\s*\(|CFStreamCreatePairWithSocketToHost|\b(connect|getaddrinfo)\s*\("#, "network access"),
        (#"NSAppleEventDescriptor\s*\([^)\n]*eventClass|\bNSUserAppleScriptTask\b"#, "running scripts"),
        (#"\b(bind|listen|accept)\s*\(|\bnw_\w+\s*\(|\bNSNetService\b|getStreamsToHost"#, "network access"),
        (#"\b(Data|String)\s*\(\s*contentsOf:"#, "reading a URL that may not be a file"),
        (#"\bxpc_connection\w*\s*\(|\bbootstrap_look_up\b|\bAuthorizationCopy\w+\b"#, "privilege escalation"),
        (#"\bNSUserUnixTask\b"#, "launching processes"),
        (#"DistributedNotificationCenter"#, "an inbound channel anyone can reach"),
        (#"DYLD_INSERT_LIBRARIES|\bprincipalClass\b"#, "loading code at runtime"),
        (#"\bNSWorkspace[^\n]{0,40}\.(activateFileViewerSelecting|selectFile)\s*\("#, "launching other apps"),
        (#"(?m)^\s*\w+\.open\s*\(\s*url"#, "launching other apps"),
    ]

    /// Text with double-quoted string literals blanked out, so copy can't trip a code-only rule.
    static func withoutStringLiterals(_ text: String) throws -> String {
        text.replacing(try Regex(#""(?:[^"\\\n]|\\.)*""#), with: "\"\"")
    }

    /// Each reason once, in rule order: several patterns can describe the same call.
    /// A line ending in this marker is allowed to use one forbidden API. Exceptions are visible in the
    /// source and greppable, rather than hidden in the rule set.
    static let allowMarker = "// security-allow:"

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
        #expect(try Self.violations(in: "let data = try Data(contentsOf: url)") == ["reading a URL that may not be a file"])
        #expect(try Self.violations(in: "popover.show(relativeTo: r, of: v, preferredEdge: .minY)").isEmpty)
        #expect(try Self.violations(in: "NSWorkspace.shared.runningApplications").isEmpty)

        // Bypasses an earlier version of this guard missed (security audit).
        #expect(try Self.violations(in: "let fd = bind(s, addr, len)") == ["network access"])
        #expect(try Self.violations(in: "listen(server, 5)") == ["network access"])
        #expect(try Self.violations(in: "let client = accept(server, nil, nil)") == ["network access"])
        #expect(try Self.violations(in: "nw_connection_create(endpoint, params)") == ["network access"])
        #expect(try Self.violations(in: "let service = NSNetService(domain: d, type: t, name: n, port: 0)") == ["network access"])
        #expect(try Self.violations(in: "Stream.getStreamsToHost(withName: h, port: 80, inputStream: &i, outputStream: &o)") == ["network access"])
        #expect(try Self.violations(in: "let data = try Data(contentsOf: remote)") == ["reading a URL that may not be a file"])
        #expect(try Self.violations(in: "let text = try String(contentsOf: remote, encoding: .utf8)") == ["reading a URL that may not be a file"])
        #expect(try Self.violations(in: "xpc_connection_create_mach_service(name, nil, 0)") == ["privilege escalation"])
        #expect(try Self.violations(in: "bootstrap_look_up(port, name, &service)") == ["privilege escalation"])
        #expect(try Self.violations(in: "AuthorizationCopyRights(auth, &rights, nil, flags, nil)") == ["privilege escalation"])
        #expect(try Self.violations(in: "let task = NSUserUnixTask(url: script)") == ["launching processes"])
        #expect(try Self.violations(in: "NSUserAppleScriptTask(url: script)") == ["running scripts"])
        #expect(try Self.violations(in: "DistributedNotificationCenter.default().addObserver(self, selector: s, name: n, object: nil)") == ["an inbound channel anyone can reach"])
        #expect(try Self.violations(in: "setenv(\"DYLD_INSERT_LIBRARIES\", path, 1)") == ["loading code at runtime"])
        #expect(try Self.violations(in: "Bundle(url: u)!.principalClass") == ["loading code at runtime"])
        #expect(try Self.violations(in: "let w = NSWorkspace.shared\nw.open(url)") == ["launching other apps"])
        #expect(try Self.violations(in: "NSWorkspace.shared.activateFileViewerSelecting([url])") == ["launching other apps"])
        // Every exception is one line, marked, and listed in SECURITY.md.
        // Launch at login is allowed; daemons and agents are not.
        #expect(try Self.violations(in: "SMAppService.mainApp.register()").isEmpty)
        #expect(try Self.violations(in: "SMAppService.daemon(plistName: p)") == ["privilege escalation"])
        #expect(try Self.violations(in: "SMAppService.agent(plistName: p)") == ["privilege escalation"])
        #expect(try Self.violations(in: "SMAppService.loginItem(identifier: id)") == ["privilege escalation"])
        #expect(Self.allowMarker == "// security-allow:")
    }

    @Test func sourcesContainNoForbiddenAPIs() throws {
        let sources = Self.packageRoot.appendingPathComponent("Sources")
        let enumerator = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let checked = text.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.contains(Self.allowMarker) }
                .joined(separator: "\n")
            let found = try Self.violations(in: checked)
            #expect(found.isEmpty, "\(file.lastPathComponent) uses a forbidden API: \(found)")
        }
    }

    @Test func buildScriptsFetchNothing() throws {
        // A guard that only reads Sources/ would not notice `curl … | sh` in a build script. Every
        // script is enumerated rather than listed, so a script added later can't escape the scan.
        let scripts = Self.packageRoot.appendingPathComponent("Scripts")
        var files = try FileManager.default.contentsOfDirectory(at: scripts, includingPropertiesForKeys: nil)
            .filter { ["sh", "swift"].contains($0.pathExtension) }
        files.append(Self.packageRoot.appendingPathComponent("Makefile"))
        #expect(files.count >= 5, "expected to find the build scripts, found \(files.count)")

        let fetchers = try Regex(#"\b(curl|wget|nc|ssh|scp|npm|pip|brew|git\s+clone)\b"#)
        for url in files {
            let text = try String(contentsOf: url, encoding: .utf8)
            // Exceptions are marked on the line that needs one, as everywhere else in this guard.
            let checked = text.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.contains(Self.allowMarker) }
                .joined(separator: "\n")
            #expect(checked.firstMatch(of: fetchers) == nil,
                    "\(url.lastPathComponent) fetches something at build time")
        }
    }

    @Test func packageHasNoDependencies() throws {
        let manifest = try String(contentsOf: Self.packageRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
        #expect(!manifest.contains(".package("))
        // Other ways code could arrive or the build could be loosened.
        for forbidden in [".binaryTarget(", ".plugin(", ".systemLibrary(", "unsafeFlags"] {
            #expect(!manifest.contains(forbidden), "Package.swift uses \(forbidden)")
        }
    }
}
