import EyesUpCore
import SwiftUI

/// The Ambient overview: what the Mac is doing right now, and why it's awake.
struct OverviewTab: View {
    let environment: AppEnvironment
    @Bindable var stats: StatsViewModel
    /// The same snapshot, claimed at a slower cadence: see DashboardState for why.
    @Bindable var slowStats: StatsViewModel

    private var snapshot: MetricsSnapshot { stats.snapshot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headline
                headlineCharts
                tiles
                otherApps
            }
            .padding(20)
        }
        .onAppear {
            stats.start()
            slowStats.start()
        }
        .onDisappear {
            stats.stop()
            slowStats.stop()
        }
    }

    private var headline: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 4) {
                Text(environment.controller.isAwake ? "Awake" : "Your Mac may sleep")
                    .font(.callout).foregroundStyle(.secondary)
                Text(countdown(now: context.date))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if environment.controller.isAwake {
                    Text(environment.controller.holds.map(\.label).joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
    }

    private func countdown(now: Date) -> String {
        guard environment.controller.isAwake else { return "Idle" }
        guard let until = environment.controller.nextDeadline else { return "No end time" }
        return TimeFormatting.countdown(until.timeIntervalSince(now))
    }

    private var headlineCharts: some View {
        HStack(spacing: 12) {
            chart("CPU", StatFormatting.percent(snapshot.cpu?.total), stats.history(.cpu), .orange)
            chart("Memory", StatFormatting.bytes(snapshot.memory?.usedBytes), stats.history(.memory), .purple)
            chart("Power", StatFormatting.watts(snapshot.power?.watts), stats.history(.power), .yellow)
        }
    }

    private func chart(_ title: String, _ value: String, _ history: [Double], _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().contentTransition(.numericText())
            Sparkline(values: history, tint: tint)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private var tiles: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
            StatTile(title: "GPU", value: StatFormatting.percent(snapshot.gpu?.utilization), detail: "utilization", symbol: "cpu.fill")
            StatTile(title: "Temperature", value: StatFormatting.celsius(snapshot.temperature?.celsius),
                     detail: snapshot.temperature.map { "hottest of \($0.sensorCount) sensors" } ?? "not available", symbol: "thermometer.medium")
            StatTile(title: "Fans", value: fanValue, detail: fanDetail, symbol: "fan")
            StatTile(title: "Performance cores", value: StatFormatting.percent(snapshot.cpu?.performance), detail: "average", symbol: "bolt.horizontal")
            StatTile(title: "Efficiency cores", value: StatFormatting.percent(snapshot.cpu?.efficiency), detail: "average", symbol: "leaf")
            StatTile(title: "Memory pressure", value: snapshot.memory?.pressure.rawValue.capitalized ?? StatFormatting.unavailable,
                     detail: "swap " + StatFormatting.bytes(snapshot.memory?.swapUsedBytes), symbol: "gauge.with.dots.needle.50percent")
            StatTile(title: "Disk free", value: StatFormatting.bytes(snapshot.storage?.freeBytes),
                     detail: "write " + StatFormatting.rate(snapshot.storage?.writeBytesPerSecond), symbol: "internaldrive")
            StatTile(title: "Network", value: StatFormatting.rate(snapshot.network?.inBytesPerSecond),
                     detail: "up " + StatFormatting.rate(snapshot.network?.outBytesPerSecond), symbol: "network")
            StatTile(title: "Uptime", value: StatFormatting.uptime(since: snapshot.system?.bootTime), detail: "since boot", symbol: "clock.arrow.circlepath")
            StatTile(title: "Last activity", value: StatFormatting.idle(snapshot.system?.idleSeconds), detail: "keyboard or mouse", symbol: "hand.point.up.left")
            StatTile(title: "Load average", value: loadValue, detail: "1 · 5 · 15 min", symbol: "chart.line.uptrend.xyaxis")
            StatTile(title: "Thermal state", value: snapshot.system?.thermal.title ?? StatFormatting.unavailable,
                     detail: "as macOS reports it", symbol: "flame")
        }
    }

    private var fanValue: String {
        guard let fans = snapshot.fans?.fans, let fastest = fans.map(\.rpm).max() else { return StatFormatting.unavailable }
        return StatFormatting.rpm(fastest)
    }

    private var fanDetail: String {
        guard let fans = snapshot.fans?.fans, !fans.isEmpty else { return "not available" }
        let maximum = fans.compactMap(\.maxRPM).max()
        return "\(fans.count) fan\(fans.count == 1 ? "" : "s")" + (maximum.map { ", max \(Int($0))" } ?? "")
    }

    private var loadValue: String {
        guard let load = snapshot.system?.loadAverage else { return StatFormatting.unavailable }
        return String(format: "%.2f", load.0)
    }

    @ViewBuilder
    private var otherApps: some View {
        if let others = snapshot.otherAssertions, !others.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Also keeping your Mac awake").font(.headline)
                ForEach(others, id: \.self) { assertion in
                    HStack {
                        Image(systemName: "app.badge").foregroundStyle(.secondary)
                        Text(assertion.processName)
                        Spacer()
                        Text(friendly(assertion.type)).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func friendly(_ assertionType: String) -> String {
        switch assertionType {
        case AssertionKind.preventDisplaySleep.ioKitType: "keeping the display on"
        case AssertionKind.preventIdleSystemSleep.ioKitType: "keeping the Mac awake"
        case AssertionKind.preventSystemSleep.ioKitType: "preventing all sleep"
        default: assertionType
        }
    }
}
