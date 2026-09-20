import Foundation
import Testing
@testable import EyesUpCore

@Suite @MainActor struct HistoryRecorderTests {
    let clock = FakeClock()

    func makeRecorder() -> (HistoryRecorder, HistoryController) {
        let history = HistoryController(store: nil, clock: clock)
        return (HistoryRecorder(history: history, clock: clock), history)
    }

    @Test func aSessionIsRecordedWhenTheLastHoldGoesAway() {
        let (recorder, history) = makeRecorder()
        recorder.holdsChanged([makeHold(label: "Timer 2h")])
        #expect(history.snapshot.sessions.isEmpty) // still running

        clock.advance(7200)
        recorder.holdsChanged([])
        #expect(history.snapshot.sessions.count == 1)
        #expect(history.snapshot.sessions.first?.duration == 7200)
        #expect(history.snapshot.sessions.first?.reasons.contains("Timer 2h") == true)
    }

    @Test func holdsComingAndGoingStayOneSession() {
        let (recorder, history) = makeRecorder()
        recorder.holdsChanged([makeHold(label: "Timer 2h")])
        clock.advance(600)
        recorder.holdsChanged([makeHold(label: "Timer 2h"), makeHold(label: "Claude running")])
        clock.advance(600)
        recorder.holdsChanged([makeHold(label: "Claude running")])
        clock.advance(600)
        recorder.holdsChanged([])
        #expect(history.snapshot.sessions.count == 1)
        #expect(history.snapshot.sessions.first?.duration == 1800)
        #expect(history.snapshot.sessions.first?.reasons.sorted() == ["Claude running", "Timer 2h"])
    }

    @Test func aSessionSpanningDaysIsRecordedOnce() {
        let (recorder, history) = makeRecorder()
        recorder.holdsChanged([makeHold(label: "Indefinitely")])
        clock.advance(3 * 86_400)
        recorder.holdsChanged([])
        #expect(history.snapshot.sessions.count == 1)
        #expect(history.snapshot.sessions.first?.duration == Double(3 * 86_400))
    }

    @Test func quittingWhileAwakeStillRecordsTheSession() {
        let (recorder, history) = makeRecorder()
        recorder.holdsChanged([makeHold(label: "Timer 1h")])
        clock.advance(1800)
        recorder.finishOpenSession()
        #expect(history.snapshot.sessions.count == 1)
        #expect(history.snapshot.sessions.first?.duration == 1800)
    }

    @Test func sleepAndWakeAreLogged() {
        let (recorder, history) = makeRecorder()
        recorder.recordSleep()
        clock.advance(3600)
        recorder.recordWake()
        #expect(history.snapshot.sleepWake.map(\.kind) == [.slept, .woke])
    }

    @Test func energyTicksLandInTheDayBucket() {
        let (recorder, history) = makeRecorder()
        recorder.energyTick(watts: 36, awake: true)
        clock.advance(100)
        recorder.energyTick(watts: 36, awake: true)
        #expect(history.snapshot.energy.count == 1)
        #expect((history.snapshot.energy.first?.kilowattHours ?? 0) > 0)
        #expect(history.snapshot.energy.first?.awakeSeconds == 100)
    }

    @Test func aSleepGapDoesNotInventEnergy() {
        let (recorder, history) = makeRecorder()
        recorder.energyTick(watts: 36, awake: true)
        clock.advance(4 * 3600)
        recorder.energyTick(watts: 36, awake: true)
        #expect(history.snapshot.energy.isEmpty)
    }
}
