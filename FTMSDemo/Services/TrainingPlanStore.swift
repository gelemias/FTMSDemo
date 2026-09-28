import Foundation

final class TrainingPlanStore {
    private enum Key {
        static let blocks = "training_plan_blocks_json"
        static let savedPlans = "saved_training_plans_json"
        static let legacySteps = "training_plan_steps_json"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadBlocks() -> [TrainingPlanBlock] {
        if let blocks = decode([TrainingPlanBlock].self, from: Key.blocks), !blocks.isEmpty {
            return blocks
        }

        guard let legacySteps = decode([TrainingPlanStep].self, from: Key.legacySteps), !legacySteps.isEmpty else {
            return TrainingPlan.todayBlocks
        }

        let migratedBlocks = legacySteps.enumerated().map { index, step in
            TrainingPlanBlock(
                kind: index == 0 ? .warmUp : (index == legacySteps.count - 1 ? .coolDown : .intervalGroup),
                durationSeconds: step.durationSeconds,
                targetSpeedKmh: step.targetSpeedKmh,
                repetitions: 1,
                recoveryDurationSeconds: 0,
                recoverySpeedKmh: step.targetSpeedKmh
            )
        }
        saveBlocks(migratedBlocks)
        return migratedBlocks
    }

    func saveBlocks(_ blocks: [TrainingPlanBlock]) {
        encode(blocks, forKey: Key.blocks)
    }

    func loadSavedPlans() -> [TrainingPlanTemplate] {
        decode([TrainingPlanTemplate].self, from: Key.savedPlans) ?? []
    }

    func saveSavedPlans(_ plans: [TrainingPlanTemplate]) {
        encode(plans, forKey: Key.savedPlans)
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from key: String) -> Value? {
        guard let data = defaults.string(forKey: key)?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<Value: Encodable>(_ value: Value, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value),
              let json = String(data: data, encoding: .utf8) else { return }
        defaults.set(json, forKey: key)
    }
}
