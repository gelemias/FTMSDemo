import Combine
import Foundation

@MainActor
final class WorkoutViewModel: ObservableObject {
    @Published var targetSpeedKmh = 10.0
    @Published var customSpeedOne: Double
    @Published var customSpeedTwo: Double
    @Published var isWorkoutRunning = false

    private let preferencesStore: WorkoutPreferencesStore

    init(preferencesStore: WorkoutPreferencesStore? = nil) {
        let store = preferencesStore ?? WorkoutPreferencesStore()
        self.preferencesStore = store
        let customSpeeds = store.loadCustomSpeeds()
        customSpeedOne = customSpeeds.first
        customSpeedTwo = customSpeeds.second
    }

    func setTargetSpeed(_ speed: Double) -> Double {
        let normalized = max(0.0, min(22.0, (speed * 10).rounded() / 10))
        targetSpeedKmh = normalized
        return normalized
    }

    func adjustSpeed(by delta: Double) -> Double {
        setTargetSpeed(targetSpeedKmh + delta)
    }

    func saveCustomSpeed(_ input: String, slot: Int) -> Bool {
        guard let value = Double(input), value >= 0.1, value <= 22.0 else { return false }
        let normalized = max(0.1, min(22.0, (value * 10).rounded() / 10))

        if slot == 1 {
            customSpeedOne = normalized
        } else {
            customSpeedTwo = normalized
        }
        preferencesStore.saveCustomSpeed(normalized, slot: slot)
        return true
    }
}
