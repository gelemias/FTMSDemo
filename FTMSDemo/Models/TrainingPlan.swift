//
//  TrainingPlan.swift
//  FTMSDemo
//

import Foundation

enum TrainingPlanPhase: String, Codable {
    case warmUp
    case interval
    case recovery
    case steadyRun
    case coolDown
}

enum TrainingPlanBlockKind: String, Codable, CaseIterable {
    case warmUp
    case intervalGroup
    case steadyRun
    case coolDown

    var title: String {
        switch self {
        case .warmUp: return "Warm up"
        case .intervalGroup: return "Intervals"
        case .steadyRun: return "Run"
        case .coolDown: return "Cool down"
        }
    }

    var icon: String {
        switch self {
        case .warmUp: return "sunrise.fill"
        case .intervalGroup: return "repeat"
        case .steadyRun: return "figure.run"
        case .coolDown: return "sunset.fill"
        }
    }
}

struct TrainingPlanStep: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let durationSeconds: TimeInterval
    var targetSpeedKmh: Double
    let phase: TrainingPlanPhase

    init(
        id: UUID = UUID(),
        title: String,
        durationSeconds: TimeInterval,
        targetSpeedKmh: Double,
        phase: TrainingPlanPhase
    ) {
        self.id = id
        self.title = title
        self.durationSeconds = durationSeconds
        self.targetSpeedKmh = targetSpeedKmh
        self.phase = phase
    }

    var durationLabel: String {
        let minutes = Int(durationSeconds) / 60
        let seconds = Int(durationSeconds) % 60
        if seconds == 0 { return "\(minutes)'" }
        return "\(minutes)'\(seconds)\""
    }
}

struct TrainingPlanBlock: Identifiable, Codable, Equatable {
    let id: UUID
    var kind: TrainingPlanBlockKind
    var durationSeconds: TimeInterval
    var targetSpeedKmh: Double
    var repetitions: Int
    var recoveryDurationSeconds: TimeInterval
    var recoverySpeedKmh: Double

    init(
        id: UUID = UUID(),
        kind: TrainingPlanBlockKind,
        durationSeconds: TimeInterval,
        targetSpeedKmh: Double,
        repetitions: Int = 1,
        recoveryDurationSeconds: TimeInterval = 0,
        recoverySpeedKmh: Double = 0
    ) {
        self.id = id
        self.kind = kind
        self.durationSeconds = durationSeconds
        self.targetSpeedKmh = targetSpeedKmh
        self.repetitions = repetitions
        self.recoveryDurationSeconds = recoveryDurationSeconds
        self.recoverySpeedKmh = recoverySpeedKmh
    }

    var title: String { kind.title }

    var totalDuration: TimeInterval {
        switch kind {
        case .intervalGroup:
            return (durationSeconds * Double(max(1, repetitions))) +
                (recoveryDurationSeconds * Double(max(0, repetitions - 1)))
        case .warmUp, .steadyRun, .coolDown:
            return durationSeconds
        }
    }

    var summary: String {
        switch kind {
        case .intervalGroup:
            return String(format: "%d × %@ at %@", max(1, repetitions), durationLabel(durationSeconds), speedLabel(targetSpeedKmh))
        case .warmUp, .steadyRun, .coolDown:
            return String(format: "%@ at %@", durationLabel(durationSeconds), speedLabel(targetSpeedKmh))
        }
    }

    var recoverySummary: String? {
        guard kind == .intervalGroup, recoveryDurationSeconds > 0 else { return nil }
        return String(format: "%@ recovery at %@", durationLabel(recoveryDurationSeconds), speedLabel(recoverySpeedKmh))
    }

    func expandedSteps() -> [TrainingPlanStep] {
        switch kind {
        case .warmUp:
            return [TrainingPlanStep(title: title, durationSeconds: durationSeconds, targetSpeedKmh: targetSpeedKmh, phase: .warmUp)]
        case .coolDown:
            return [TrainingPlanStep(title: title, durationSeconds: durationSeconds, targetSpeedKmh: targetSpeedKmh, phase: .coolDown)]
        case .steadyRun:
            return [TrainingPlanStep(title: title, durationSeconds: durationSeconds, targetSpeedKmh: targetSpeedKmh, phase: .steadyRun)]
        case .intervalGroup:
            var steps: [TrainingPlanStep] = []
            let count = max(1, repetitions)
            for repetition in 1...count {
                steps.append(TrainingPlanStep(title: String(format: "Interval %d of %d", repetition, count), durationSeconds: durationSeconds, targetSpeedKmh: targetSpeedKmh, phase: .interval))
                if repetition < count, recoveryDurationSeconds > 0 {
                    steps.append(TrainingPlanStep(title: String(format: "Recovery %d of %d", repetition, count - 1), durationSeconds: recoveryDurationSeconds, targetSpeedKmh: recoverySpeedKmh, phase: .recovery))
                }
            }
            return steps
        }
    }

    private func durationLabel(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let remainder = Int(seconds) % 60
        if remainder == 0 { return String(format: "%d min", minutes) }
        return String(format: "%d:%02d", minutes, remainder)
    }

    private func speedLabel(_ speed: Double) -> String {
        String(format: "%.1f km/h", speed)
    }
}

struct TrainingPlanTemplate: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var blocks: [TrainingPlanBlock]
    var createdAt: Date

    init(id: UUID = UUID(), name: String, blocks: [TrainingPlanBlock], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.blocks = blocks
        self.createdAt = createdAt
    }
}

struct TrainingPlan: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let steps: [TrainingPlanStep]

    var totalDuration: TimeInterval {
        steps.reduce(0) { $0 + $1.durationSeconds }
    }

    static let today = TrainingPlan(
        name: "Intervals for today",
        steps: [
            TrainingPlanStep(title: "Warm up", durationSeconds: 12 * 60, targetSpeedKmh: 8.0, phase: .warmUp),
            intervalStep, recoveryStep, intervalStep, recoveryStep,
            intervalStep, recoveryStep, intervalStep, recoveryStep,
            TrainingPlanStep(title: "Cool down", durationSeconds: 10 * 60, targetSpeedKmh: 6.0, phase: .coolDown)
        ]
    )

    private static var intervalStep: TrainingPlanStep {
        TrainingPlanStep(title: "Interval", durationSeconds: 4 * 60, targetSpeedKmh: 13.0, phase: .interval)
    }

    private static var recoveryStep: TrainingPlanStep {
        TrainingPlanStep(title: "Recovery", durationSeconds: 2 * 60 + 30, targetSpeedKmh: 8.0, phase: .recovery)
    }

    init(id: UUID = UUID(), name: String, steps: [TrainingPlanStep]) {
        self.id = id
        self.name = name
        self.steps = steps
    }
}

extension TrainingPlan {
    static let todayBlocks: [TrainingPlanBlock] = [
        TrainingPlanBlock(kind: .warmUp, durationSeconds: 15 * 60, targetSpeedKmh: 12.0),
        TrainingPlanBlock(kind: .intervalGroup, durationSeconds: 3 * 60, targetSpeedKmh: 16.0, repetitions: 5, recoveryDurationSeconds: 90, recoverySpeedKmh: 10.0),
        TrainingPlanBlock(kind: .coolDown, durationSeconds: 5 * 60, targetSpeedKmh: 8.0)
    ]

    static var todayFromBlocks: TrainingPlan {
        TrainingPlan(name: "Speed builder", blocks: todayBlocks)
    }

    init(id: UUID = UUID(), name: String, blocks: [TrainingPlanBlock]) {
        self.id = id
        self.name = name
        self.steps = blocks.flatMap { $0.expandedSteps() }
    }
}
