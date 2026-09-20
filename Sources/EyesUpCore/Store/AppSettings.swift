import Foundation
import Observation

/// What the menu-bar item shows beside its ring (spec §7.1).
public enum MenuBarReadout: String, Codable, CaseIterable, Sendable {
    case iconOnly, timer, timerAndCPU, timerAndPower, timerCPUAndPower

    public var title: String {
        switch self {
        case .iconOnly: "Icon only"
        case .timer: "Icon and time left"
        case .timerAndCPU: "Icon, time and CPU"
        case .timerAndPower: "Icon, time and power"
        case .timerCPUAndPower: "Icon, time, CPU and power"
        }
    }

    /// Nothing is sampled for the first two, so the menu bar costs nothing at rest.
    public var metricIDs: Set<MetricID> {
        switch self {
        case .iconOnly, .timer: []
        case .timerAndCPU: [.cpu]
        case .timerAndPower: [.power]
        case .timerCPUAndPower: [.cpu, .power]
        }
    }
}

/// Where the floating HUD sits, in screen coordinates.
public struct HUDPosition: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// User settings (spec §8). Decoding tolerates missing keys so later versions can add fields
/// without a schema bump, and out-of-range values fall back to their defaults.
public struct AppSettings: Codable, Equatable, Sendable {
    public static let minSafetyCapHours = 1.0
    public static let maxSafetyCapHours = 168.0
    /// Longest a "pause until" may sit in the future before it's treated as stale.
    public static let maxPauseDays = 30.0
    public static let maxPresets = 8
    public static let maxElectricityRate = 10.0
    public static let minHeadsUpLeadMinutes = 1.0
    public static let maxHeadsUpLeadMinutes = 60.0

    public var safetyCapHours: Double?
    public var thermalAutoRelease: Bool
    public var automationEnabled: Bool
    public var triggerPause: TriggerPause
    public var menuBarReadout: MenuBarReadout
    public var hudVisible: Bool
    public var hudPosition: HUDPosition?
    /// Money per kilowatt-hour, in the system currency. nil means "don't show money at all".
    public var electricityRate: Double?
    public var presets: [TimeInterval]
    public var headsUpLeadMinutes: Double
    public var keepDisplayOnByDefault: Bool
    public var launchAtLogin: Bool

    public init(
        safetyCapHours: Double? = nil,
        thermalAutoRelease: Bool = true,
        automationEnabled: Bool = false,
        triggerPause: TriggerPause = .none,
        menuBarReadout: MenuBarReadout = .timer,
        hudVisible: Bool = false,
        hudPosition: HUDPosition? = nil,
        electricityRate: Double? = nil,
        presets: [TimeInterval] = [900, 3600, 7200, 14400],
        headsUpLeadMinutes: Double = 5,
        keepDisplayOnByDefault: Bool = false,
        launchAtLogin: Bool = false
    ) {
        self.safetyCapHours = safetyCapHours
        self.thermalAutoRelease = thermalAutoRelease
        self.automationEnabled = automationEnabled
        self.triggerPause = triggerPause
        self.menuBarReadout = menuBarReadout
        self.hudVisible = hudVisible
        self.hudPosition = hudPosition
        self.electricityRate = electricityRate
        self.presets = presets
        self.headsUpLeadMinutes = headsUpLeadMinutes
        self.keepDisplayOnByDefault = keepDisplayOnByDefault
        self.launchAtLogin = launchAtLogin
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        safetyCapHours = try container.decodeIfPresent(Double.self, forKey: .safetyCapHours)
        thermalAutoRelease = try container.decodeIfPresent(Bool.self, forKey: .thermalAutoRelease) ?? true
        automationEnabled = try container.decodeIfPresent(Bool.self, forKey: .automationEnabled) ?? false
        triggerPause = try container.decodeIfPresent(TriggerPause.self, forKey: .triggerPause) ?? .none
        // An unknown value from a hand-edited file falls back rather than failing the whole load.
        menuBarReadout = (try? container.decodeIfPresent(MenuBarReadout.self, forKey: .menuBarReadout)) ?? .timer
        hudVisible = try container.decodeIfPresent(Bool.self, forKey: .hudVisible) ?? false
        hudPosition = try container.decodeIfPresent(HUDPosition.self, forKey: .hudPosition)
        electricityRate = try container.decodeIfPresent(Double.self, forKey: .electricityRate)
        presets = try container.decodeIfPresent([TimeInterval].self, forKey: .presets) ?? [900, 3600, 7200, 14400]
        headsUpLeadMinutes = try container.decodeIfPresent(Double.self, forKey: .headsUpLeadMinutes) ?? 5
        keepDisplayOnByDefault = try container.decodeIfPresent(Bool.self, forKey: .keepDisplayOnByDefault) ?? false
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
    }

    public func validated(now: Date = Date()) -> AppSettings {
        var settings = self
        if let hours = settings.safetyCapHours {
            let usable = hours.isFinite && hours >= Self.minSafetyCapHours && hours <= Self.maxSafetyCapHours
            settings.safetyCapHours = usable ? hours : nil
        }
        if case .until(let date) = settings.triggerPause,
           date.timeIntervalSince(now) > Self.maxPauseDays * 86_400 {
            settings.triggerPause = .none
        }
        if let position = settings.hudPosition {
            let sane = position.x.isFinite && position.y.isFinite
                && abs(position.x) < 100_000 && abs(position.y) < 100_000
            settings.hudPosition = sane ? position : nil
        }
        if let rate = settings.electricityRate {
            let usable = rate.isFinite && rate > 0 && rate <= Self.maxElectricityRate
            settings.electricityRate = usable ? rate : nil
        }
        let usablePresets = settings.presets
            .filter { $0.isFinite && $0 >= 60 && $0 <= AwakeController.maxManualDuration }
            .sorted()
        settings.presets = usablePresets.isEmpty ? AppSettings().presets : Array(usablePresets.prefix(Self.maxPresets))
        if !settings.headsUpLeadMinutes.isFinite
            || settings.headsUpLeadMinutes < Self.minHeadsUpLeadMinutes
            || settings.headsUpLeadMinutes > Self.maxHeadsUpLeadMinutes {
            settings.headsUpLeadMinutes = 5
        }
        return settings
    }

    /// A settings file the user can keep or move to another Mac.
    public func exportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Anything unreadable throws; anything out of range is clamped by `validated()`.
    public static func imported(from data: Data) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: data)
    }
}

/// Holds the settings, saves every change, and tells whoever cares.
@MainActor
@Observable
public final class SettingsController {
    public private(set) var settings: AppSettings
    public internal(set) var storeNotice: String?
    @ObservationIgnored public var onChange: ((AppSettings) -> Void)?

    @ObservationIgnored private let store: JSONFileStore<AppSettings>?

    public init(store: JSONFileStore<AppSettings>?, settings: AppSettings = AppSettings()) {
        self.store = store
        self.settings = settings
    }

    public func load() {
        guard let store else { return }
        switch store.load() {
        case .missing:
            break
        case .loaded(let saved):
            settings = saved.validated()
        case .corrupt:
            storeNotice = "Settings couldn't be read, so they were reset to their defaults."
        }
        onChange?(settings)
    }

    public func export() throws -> Data {
        try settings.exportData()
    }

    public func importSettings(_ data: Data) throws {
        let imported = try AppSettings.imported(from: data)
        settings = imported.validated()
        persist()
        onChange?(settings)
    }

    /// Surfaces a problem in the Settings tab without throwing it away.
    public func reportNotice(_ message: String) {
        storeNotice = message
    }

    public func update(_ change: (inout AppSettings) -> Void) {
        var updated = settings
        change(&updated)
        settings = updated.validated()
        persist()
        onChange?(settings)
    }

    private func persist() {
        guard let store else { return }
        do {
            try store.save(settings)
        } catch {
            storeNotice = "Couldn't save settings: \(error.localizedDescription)"
        }
    }
}
