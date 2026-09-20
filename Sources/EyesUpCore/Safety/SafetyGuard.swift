import Foundation

/// Spec §4.5: when the Mac reaches a critical thermal state, stop keeping it awake.
@MainActor
public final class SafetyGuard {
    public var thermalAutoRelease = true
    public var onThermalRelease: (() -> Void)?

    private let controller: AwakeController
    private let thermal: any ThermalMonitoring
    private var observation: (any ScheduledTask)?

    public init(controller: AwakeController, thermal: any ThermalMonitoring) {
        self.controller = controller
        self.thermal = thermal
    }

    public func start() {
        observation = thermal.observeChanges { [weak self] in self?.evaluate() }
        evaluate()
    }

    public func stop() {
        observation?.cancel()
        observation = nil
    }

    public func evaluate() {
        guard thermalAutoRelease, thermal.currentLevel() == .critical, controller.isAwake else { return }
        controller.releaseAllForSafety()
        onThermalRelease?()
    }
}

/// Pushes saved settings into the pieces that act on them.
@MainActor
public enum SettingsApplier {
    public static func apply(
        _ settings: AppSettings,
        controller: AwakeController,
        engine: TriggerEngine,
        safety: SafetyGuard
    ) {
        controller.setSafetyCap(settings.safetyCapHours.map { $0 * 3600 })
        var extra: SleepPolicy = []
        if settings.keepDiskAwake { extra.insert(.disk) }
        if settings.onlyOnACPower { extra.insert(.systemOnAC) }
        controller.extraPolicy = extra
        safety.thermalAutoRelease = settings.thermalAutoRelease
        if engine.pause != settings.triggerPause { engine.setPause(settings.triggerPause) }
    }
}
