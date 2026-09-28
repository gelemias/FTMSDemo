import SwiftUI

struct MetricCustomizationView: View {
    @Binding var preferences: [MetricPreference]
    let onMove: (IndexSet, Int) -> Void
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach($preferences) { $preference in
                    HStack {
                        Text(title(for: preference.id))
                        Spacer()
                        Toggle("Visible", isOn: $preference.isVisible)
                            .labelsHidden()
                    }
                }
                .onMove(perform: onMove)
            }
            .navigationTitle("Customize Metrics")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onDone)
                }
            }
        }
    }

    private func title(for metric: MetricID) -> String {
        switch metric {
        case .distance: return "Distance"
        case .pace: return "Pace"
        case .speed: return "Speed"
        case .incline: return "Incline"
        case .cadence: return "Cadence"
        case .heartRate: return "Heart Rate"
        }
    }
}

struct MetricRowView: View {
    let metricID: MetricID
    let treadmillData: TreadmillData

    @ViewBuilder
    var body: some View {
        switch metricID {
        case .distance:
            DataRow(label: "Distance", value: treadmillData.distanceKilometers, unit: "km")
        case .pace:
            DataRow(label: "Pace", value: treadmillData.paceMinPerKm, unit: "min/km")
        case .speed:
            DataRow(label: "Speed", value: treadmillData.speedKmh, unit: "km/h")
        case .incline:
            DataRow(label: "Incline", value: treadmillData.incline, unit: "%")
        case .cadence:
            DataRow(label: "Cadence (est.)", value: treadmillData.cadenceSpm, unit: "spm")
        case .heartRate:
            DataRow(label: "Heart Rate", value: treadmillData.heartRate, unit: "bpm")
        }
    }
}
