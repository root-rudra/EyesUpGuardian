import Foundation
import Testing
@testable import EyesUpCore

@Suite struct ProcessOriginTests {
    @Test(arguments: [
        "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder",
        "/System/Applications/Mail.app/Contents/MacOS/Mail",
        "/usr/libexec/secinitd",
        "/usr/sbin/cfprefsd",
        "/bin/zsh",
        "/sbin/launchd",
        "/Library/Apple/System/Library/CoreServices/XProtect.app/Contents/MacOS/XProtect",
    ])
    func macOSOwnsTheProtectedPaths(path: String) {
        #expect(ProcessOrigin.of(executablePath: path) == .macOS)
    }

    @Test(arguments: [
        "/Applications/Claude.app/Contents/MacOS/Claude",
        "/Applications/Xcode.app/Contents/MacOS/Xcode",
        "/Users/someone/Applications/Thing.app/Contents/MacOS/Thing",
        "/opt/homebrew/bin/node",
        "/usr/local/bin/python3",
        "/Library/Application Support/Vendor/Helper",
        "/private/var/folders/xy/T/AppTranslocation/Thing.app/Contents/MacOS/Thing",
    ])
    func everythingElseCountsAsInstalled(path: String) {
        #expect(ProcessOrigin.of(executablePath: path) == .installed)
    }

    /// The data volume is reached through a firmlink under /System, but nothing there is Apple's.
    @Test func theDataVolumeIsNotTheSystemVolume() {
        #expect(ProcessOrigin.of(executablePath: "/System/Volumes/Data/Applications/Foo.app/Contents/MacOS/Foo") == .installed)
        #expect(ProcessOrigin.of(executablePath: "/System/Volumes/Data/opt/thing/bin/thing") == .installed)
        #expect(ProcessOrigin.of(executablePath: "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock") == .macOS)
    }

    /// `/usr/local` is the one writable part of `/usr`, so it must not be mistaken for the OS.
    @Test func usrLocalIsNotTheSystem() {
        #expect(ProcessOrigin.of(executablePath: "/usr/local/bin/brew") == .installed)
        #expect(ProcessOrigin.of(executablePath: "/usr/bin/ssh") == .macOS)
    }

    @Test func anUnreadablePathIsSaidToBeUnknownRatherThanGuessed() {
        #expect(ProcessOrigin.of(executablePath: nil) == .unknown)
        #expect(ProcessOrigin.of(executablePath: "") == .unknown)
        #expect(ProcessOrigin.of(executablePath: "kernel_task") == .unknown)
    }
}
