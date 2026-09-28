import ActivityKit
import Combine
import Foundation
import HealthKit

struct TrainingPlanActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phaseTitle: String
        var phaseNumber: Int
        var totalPhases: Int
        var targetSpeedKmh: Double
        var secondsRemaining: Int
        var totalSecondsRemaining: Int
        var phaseProgress: Double
        var workoutProgress: Double
        var isComplete: Bool
    }

    var workoutName: String
    var treadmillName: String
}

@MainActor
final class TrainingPlanRunner: NSObject, ObservableObject {
    @Published private(set) var currentStep: TrainingPlanStep?
    @Published private(set) var secondsRemaining = 0
    @Published private(set) var totalSecondsRemaining = 0
    @Published private(set) var phaseProgress = 0.0
    @Published private(set) var workoutProgress = 0.0
    @Published private(set) var isRunning = false

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var timer: DispatchSourceTimer?
    private var steps: [TrainingPlanStep] = []
    private var startedAt: Date?
    private var lastCommandedStepID: UUID?
    private var sendSpeed: ((Double) -> Void)?
    private var startTreadmill: (() -> Void)?
    private var stopTreadmill: (() -> Void)?
    private var activity: Activity<TrainingPlanActivityAttributes>?
    private var workoutName = "Training plan"
    private var treadmillName = "Treadmill"

    func start(
        blocks: [TrainingPlanBlock],
        workoutName: String,
        treadmillName: String,
        sendSpeed: @escaping (Double) -> Void,
        startTreadmill: @escaping () -> Void,
        stopTreadmill: @escaping () -> Void
    ) {
        guard !blocks.isEmpty else { return }

        self.steps = blocks.flatMap { $0.expandedSteps() }
        self.workoutName = workoutName
        self.treadmillName = treadmillName
        self.sendSpeed = sendSpeed
        self.startTreadmill = startTreadmill
        self.stopTreadmill = stopTreadmill
        self.startedAt = Date()
        self.isRunning = true

        beginWorkoutSessionIfAvailable()
        startLiveActivity()
        self.startTreadmill?()
        tick()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in self?.tick() }
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        guard isRunning || startedAt != nil else { return }
        timer?.cancel()
        timer = nil
        stopTreadmill?()
        workoutSession?.end()
        workoutSession = nil
        endLiveActivity()
        isRunning = false
        startedAt = nil
        currentStep = nil
        secondsRemaining = 0
        totalSecondsRemaining = 0
        phaseProgress = 0
        workoutProgress = 0
        lastCommandedStepID = nil
    }

    func refresh() {
        guard isRunning else { return }
        tick()
    }

    private func tick(now: Date = Date()) {
        guard let startedAt, !steps.isEmpty else { return }
        let elapsed = max(0, now.timeIntervalSince(startedAt))
        var consumed: TimeInterval = 0
        var selectedStep: TrainingPlanStep?
        var selectedIndex = 0
        var elapsedInStep = 0.0

        for (index, step) in steps.enumerated() {
            if elapsed < consumed + step.durationSeconds {
                selectedStep = step
                selectedIndex = index
                elapsedInStep = elapsed - consumed
                break
            }
            consumed += step.durationSeconds
        }

        guard let step = selectedStep else {
            currentStep = nil
            secondsRemaining = 0
            totalSecondsRemaining = 0
            isRunning = false
            timer?.cancel()
            timer = nil
            stopTreadmill?()
            workoutSession?.end()
            workoutSession = nil
            endLiveActivity(isComplete: true)
            self.startedAt = nil
            return
        }

        let remaining = max(0, Int(ceil(step.durationSeconds - elapsedInStep)))
        let totalRemaining = max(0, Int(ceil(steps.dropFirst(selectedIndex).reduce(0) { $0 + $1.durationSeconds } - elapsedInStep)))
        let totalDuration = steps.reduce(0) { $0 + $1.durationSeconds }
        let elapsedBeforeStep = consumed + elapsedInStep
        phaseProgress = min(1, max(0, elapsedInStep / max(1, step.durationSeconds)))
        workoutProgress = min(1, max(0, elapsedBeforeStep / max(1, totalDuration)))
        currentStep = step
        secondsRemaining = remaining
        totalSecondsRemaining = totalRemaining

        if lastCommandedStepID != step.id {
            lastCommandedStepID = step.id
            sendSpeed?(step.targetSpeedKmh)
        }
        updateLiveActivity(step: step, index: selectedIndex, secondsRemaining: remaining, totalSecondsRemaining: totalRemaining)
    }

    private func beginWorkoutSessionIfAvailable() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let workoutType = HKObjectType.workoutType()
        healthStore.requestAuthorization(toShare: [workoutType], read: []) { [weak self] _, error in
            if let error {
                print("Could not authorize workout session: \(error)")
            }
            Task { @MainActor [weak self] in
                self?.createWorkoutSession()
            }
        }
    }

    private func createWorkoutSession() {
        do {
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .running
            configuration.locationType = .indoor
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            session.delegate = self
            workoutSession = session
            session.startActivity(with: Date())
        } catch {
            print("Could not start workout session: \(error)")
        }
    }

    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = TrainingPlanActivityAttributes(workoutName: workoutName, treadmillName: treadmillName)
        let state = TrainingPlanActivityAttributes.ContentState(
            phaseTitle: steps.first?.title ?? "Starting",
            phaseNumber: 1,
            totalPhases: steps.count,
            targetSpeedKmh: steps.first?.targetSpeedKmh ?? 0,
            secondsRemaining: Int(steps.first?.durationSeconds ?? 0),
            totalSecondsRemaining: Int(steps.reduce(0) { $0 + $1.durationSeconds }),
            phaseProgress: 0,
            workoutProgress: 0,
            isComplete: false
        )
        do {
            activity = try Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: nil))
        } catch {
            print("Could not start training Live Activity: \(error)")
        }
    }

    private func updateLiveActivity(step: TrainingPlanStep, index: Int, secondsRemaining: Int, totalSecondsRemaining: Int) {
        guard let activity else { return }
        let state = TrainingPlanActivityAttributes.ContentState(
            phaseTitle: step.title,
            phaseNumber: index + 1,
            totalPhases: steps.count,
            targetSpeedKmh: step.targetSpeedKmh,
            secondsRemaining: secondsRemaining,
            totalSecondsRemaining: totalSecondsRemaining,
            phaseProgress: phaseProgress,
            workoutProgress: workoutProgress,
            isComplete: false
        )
        Task {
            await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(3)))
        }
    }

    private func endLiveActivity(isComplete: Bool = false) {
        guard let activity else { return }
        let state = TrainingPlanActivityAttributes.ContentState(
            phaseTitle: isComplete ? "Workout complete" : "Workout stopped",
            phaseNumber: steps.count,
            totalPhases: steps.count,
            targetSpeedKmh: currentStep?.targetSpeedKmh ?? 0,
            secondsRemaining: 0,
            totalSecondsRemaining: 0,
            phaseProgress: 1,
            workoutProgress: isComplete ? 1 : workoutProgress,
            isComplete: isComplete
        )
        Task {
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: isComplete ? .after(Date().addingTimeInterval(30)) : .immediate)
        }
        self.activity = nil
    }
}

extension TrainingPlanRunner: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("Workout session failed: \(error)")
    }
}
