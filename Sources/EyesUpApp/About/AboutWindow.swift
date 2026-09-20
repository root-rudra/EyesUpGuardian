import AppKit
import EyesUpCore
import SwiftUI

/// A small About panel: what this is, which version, and where to check what it's doing.
struct AboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            Text("EyesUpGuardian").font(.title2.bold())
            Text("Version \(version)").font(.callout).foregroundStyle(.secondary)
            Text("Keeps your Mac awake, and shows you what it's doing.")
                .font(.callout)
                .multilineTextAlignment(.center)
            Text("It runs no commands, uses no network, and needs no admin rights.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Check what it's holding:  pmset -g assertions | grep EyesUpGuardian")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
        .padding(24)
        .frame(width: 340)
    }
}

@MainActor
final class AboutWindowController {
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About EyesUpGuardian"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: AboutView())
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        self.window = window
    }
}
