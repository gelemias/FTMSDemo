import Foundation

enum MetricID: String, CaseIterable, Codable, Identifiable {
    case distance
    case pace
    case speed
    case incline
    case cadence
    case heartRate

    var id: String { rawValue }
}

struct MetricPreference: Identifiable, Codable, Equatable {
    let id: MetricID
    var isVisible: Bool
}

enum WorkoutInputSanitizer {
    static func numericText(_ input: String) -> String {
        let normalized = input.replacingOccurrences(of: ",", with: ".")
        var result = ""
        var hasDecimalSeparator = false

        for character in normalized {
            if character.isNumber {
                result.append(character)
            } else if character == ".", !hasDecimalSeparator {
                hasDecimalSeparator = true
                result.append(character)
            }
        }

        return result
    }
}

final class WorkoutPreferencesStore {
    private enum Key {
        static let metricPreferences = "metric_preferences_json"
        static let customSpeedOne = "custom_speed_one_kmh"
        static let customSpeedTwo = "custom_speed_two_kmh"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadMetricPreferences() -> [MetricPreference] {
        guard let json = defaults.string(forKey: Key.metricPreferences),
              let data = json.data(using: .utf8),
              let preferences = try? JSONDecoder().decode([MetricPreference].self, from: data) else {
            return Self.defaultMetricPreferences
        }

        return Self.normalizedMetricPreferences(preferences)
    }

    func saveMetricPreferences(_ preferences: [MetricPreference]) {
        guard let data = try? JSONEncoder().encode(preferences),
              let json = String(data: data, encoding: .utf8) else { return }
        defaults.set(json, forKey: Key.metricPreferences)
    }

    func loadCustomSpeeds() -> (first: Double, second: Double) {
        (
            defaults.object(forKey: Key.customSpeedOne) as? Double ?? 8.0,
            defaults.object(forKey: Key.customSpeedTwo) as? Double ?? 13.0
        )
    }

    func saveCustomSpeed(_ speed: Double, slot: Int) {
        let key = slot == 1 ? Key.customSpeedOne : Key.customSpeedTwo
        defaults.set(speed, forKey: key)
    }

    static let defaultMetricPreferences = MetricID.allCases.map {
        MetricPreference(id: $0, isVisible: true)
    }

    static func normalizedMetricPreferences(_ preferences: [MetricPreference]) -> [MetricPreference] {
        var seen = Set<MetricID>()
        var normalized: [MetricPreference] = []

        for preference in preferences where !seen.contains(preference.id) {
            normalized.append(preference)
            seen.insert(preference.id)
        }

        for metric in MetricID.allCases where !seen.contains(metric) {
            normalized.append(MetricPreference(id: metric, isVisible: true))
        }

        return normalized
    }
}
