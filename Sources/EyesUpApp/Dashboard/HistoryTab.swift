import EyesUpCore
import SwiftUI

enum HistoryRange: String, CaseIterable, Identifiable {
    case week, month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: "7 days"
        case .month: "30 days"
        }
    }

    var days: Int {
        switch self {
        case .week: 7
        case .month: 30
        }
    }
}

@MainActor
@Observable
final class HistoryTabState {
    var range: HistoryRange = .week
}

/// What the Mac has been doing: how long it was kept awake, what kept it awake, what that cost,
/// and when it slept.
struct HistoryTab: View {
    let environment: AppEnvironment
    @Bindable var state: HistoryTabState

    private var snapshot: HistorySnapshot { environment.history.snapshot }
    private var since: Date { Calendar.current.startOfDay(for: Date().addingTimeInterval(-Double(state.range.days - 1) * 86_400)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                dayChart
                totals
                topReasons
                sessionList
                sleepLog
                if let notice = environment.history.storeNotice {
                    Label(notice, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
    }

    private var header: some View {
        HStack {
            Text("History").font(.title2.bold())
            Spacer()
            Picker("Range", selection: $state.range) {
                ForEach(HistoryRange.allCases) { range in Text(range.title).tag(range) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
    }

    /// Hours kept awake per day, oldest on the left.
    private var dayChart: some View {
        let days = dailyAwakeHours()
        let tallest = max(days.map(\.hours).max() ?? 1, 0.5)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(days, id: \.day) { entry in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(entry.hours > 0 ? Color.orange.opacity(0.85) : Color.secondary.opacity(0.2))
                            .frame(height: max(3, CGFloat(entry.hours / tallest) * 90))
                            .accessibilityLabel("\(entry.label): \(TimeFormatting.duration(entry.hours * 3600)) awake")
                        Text(entry.label).font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 110, alignment: .bottom)
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private var totals: some View {
        let awake = snapshot.awakeSeconds(since: since)
        let sessions = snapshot.sessions.filter { $0.endedAt >= since }
        let kilowattHours = snapshot.kilowattHours(since: since)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
            StatTile(title: "Kept awake", value: TimeFormatting.duration(awake), detail: state.range.title, symbol: "eye")
            StatTile(title: "Sessions", value: "\(sessions.count)", detail: "in this range", symbol: "list.number")
            StatTile(title: "Energy", value: kilowattHours > 0 ? String(format: "%.2f kWh", kilowattHours) : StatFormatting.unavailable,
                     detail: energyDetail(kilowattHours), symbol: "bolt.circle")
            StatTile(title: "Longest", value: TimeFormatting.duration(sessions.map(\.duration).max() ?? 0),
                     detail: "single session", symbol: "hourglass")
        }
    }

    private func energyDetail(_ kilowattHours: Double) -> String {
        guard kilowattHours > 0 else { return "needs power readings" }
        return EnergyCost.money(kilowattHours, ratePerKilowattHour: environment.settings.settings.electricityRate)
            ?? "set a rate in Settings"
    }

    @ViewBuilder
    private var topReasons: some View {
        let ranked = rankedReasons()
        if !ranked.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("What kept it awake").font(.headline)
                ForEach(ranked.prefix(5), id: \.reason) { entry in
                    HStack {
                        Text(entry.reason).lineLimit(1)
                        Spacer()
                        Text(TimeFormatting.duration(entry.seconds)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .font(.callout)
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var sessionList: some View {
        let sessions = snapshot.sessions.filter { $0.endedAt >= since }.sorted { $0.startedAt > $1.startedAt }
        VStack(alignment: .leading, spacing: 6) {
            Text("Sessions").font(.headline)
            if sessions.isEmpty {
                Text("Nothing yet in this range.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(sessions.prefix(50)) { session in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.callout)
                        Text(session.reasons.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text(TimeFormatting.duration(session.duration)).monospacedDigit().font(.callout)
                }
                .padding(8)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    @ViewBuilder
    private var sleepLog: some View {
        let events = snapshot.sleepWake.filter { $0.at >= since }.sorted { $0.at > $1.at }
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sleep and wake").font(.headline)
                ForEach(events.prefix(10), id: \.self) { event in
                    HStack {
                        Image(systemName: event.kind == .slept ? "moon.fill" : "sun.max.fill")
                            .foregroundStyle(event.kind == .slept ? .purple : .orange)
                        Text(event.kind == .slept ? "Went to sleep" : "Woke up")
                        Spacer()
                        Text(event.at.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func dailyAwakeHours() -> [(day: Date, label: String, hours: Double)] {
        let calendar = Calendar.current
        return (0..<state.range.days).reversed().map { offset in
            let day = calendar.startOfDay(for: Date().addingTimeInterval(-Double(offset) * 86_400))
            let next = day.addingTimeInterval(86_400)
            let seconds = snapshot.sessions.reduce(0.0) { total, session in
                let start = max(session.startedAt, day)
                let end = min(session.endedAt, next)
                return total + max(0, end.timeIntervalSince(start))
            }
            let label = state.range == .week
                ? day.formatted(.dateTime.weekday(.narrow))
                : day.formatted(.dateTime.day())
            return (day: day, label: label, hours: seconds / 3600)
        }
    }

    private func rankedReasons() -> [(reason: String, seconds: TimeInterval)] {
        var totals: [String: TimeInterval] = [:]
        for session in snapshot.sessions where session.endedAt >= since {
            // A session's time is shared evenly between the reasons that held it.
            guard !session.reasons.isEmpty else { continue }
            let share = session.duration / Double(session.reasons.count)
            for reason in session.reasons { totals[reason, default: 0] += share }
        }
        return totals.map { (reason: $0.key, seconds: $0.value) }.sorted { $0.seconds > $1.seconds }
    }
}
