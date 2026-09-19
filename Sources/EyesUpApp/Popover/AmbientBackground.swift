import AppKit
import SwiftUI

/// Ambient style: a soft glow whose color follows state. It animates only when the mood changes, never on a loop.
struct AmbientBackground: View {
    enum Mood: Equatable { case idle, awake }

    let mood: Mood
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if reduceTransparency { Color(nsColor: .windowBackgroundColor) }
            RadialGradient(colors: [primary.opacity(0.55), .clear], center: .topLeading, startRadius: 0, endRadius: 300)
            RadialGradient(colors: [secondary.opacity(0.4), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 300)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: mood)
        .allowsHitTesting(false)
    }

    var primary: Color {
        mood == .awake ? Color(red: 1.0, green: 0.63, blue: 0.35) : Color(red: 0.45, green: 0.40, blue: 0.75)
    }

    private var secondary: Color {
        mood == .awake ? Color(red: 0.55, green: 0.35, blue: 1.0) : Color(red: 0.25, green: 0.25, blue: 0.45)
    }
}
