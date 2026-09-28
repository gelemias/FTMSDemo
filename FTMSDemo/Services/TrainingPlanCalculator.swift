import Foundation

enum TrainingPlanCalculator {
    static func steps(from blocks: [TrainingPlanBlock]) -> [TrainingPlanStep] {
        blocks.flatMap { $0.expandedSteps() }
    }

    static func duration(of blocks: [TrainingPlanBlock]) -> TimeInterval {
        blocks.reduce(0) { $0 + $1.totalDuration }
    }

    static func intervalCount(in blocks: [TrainingPlanBlock]) -> Int {
        blocks
            .filter { $0.kind == .intervalGroup }
            .reduce(0) { $0 + max(1, $1.repetitions) }
    }

    static func currentStep(
        in blocks: [TrainingPlanBlock],
        elapsed: TimeInterval,
        isRunning: Bool
    ) -> TrainingPlanStep? {
        let planSteps = steps(from: blocks)
        guard isRunning else { return planSteps.first }

        var consumed: TimeInterval = 0
        for step in planSteps {
            consumed += step.durationSeconds
            if elapsed < consumed { return step }
        }
        return nil
    }

    static func elapsedInCurrentStep(
        in blocks: [TrainingPlanBlock],
        elapsed: TimeInterval
    ) -> TimeInterval {
        var consumed: TimeInterval = 0
        for step in steps(from: blocks) {
            if elapsed < consumed + step.durationSeconds {
                return max(0, elapsed - consumed)
            }
            consumed += step.durationSeconds
        }
        return 0
    }

    static func durationSummary(_ seconds: TimeInterval) -> String {
        let wholeMinutes = Int(seconds) / 60
        let remainder = Int(seconds) % 60
        if remainder == 0 { return "\(wholeMinutes) min total" }
        return String(format: "%d:%02d total", wholeMinutes, remainder)
    }

    static func timeLabel(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
