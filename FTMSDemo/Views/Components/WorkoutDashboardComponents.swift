import SwiftUI

struct WorkoutStatusStripView: View {
    let isWorkoutRunning: Bool
    let connectedDeviceName: String?
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(WorkoutTheme.controlAccent)
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(isWorkoutRunning ? "WORKOUT LIVE" : "MACHINE READY")
                    .font(.caption.weight(.black))
                    .tracking(1.1)
                Text(connectedDeviceName ?? "Treadmill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(WorkoutTheme.muted)
            }
            Spacer()
            if isLoading { ProgressView().tint(WorkoutTheme.controlAccent) }
        }
        .padding(.horizontal, 4)
    }
}

struct PrimaryMetricCardView: View {
    let treadmillData: TreadmillData
    let visibleMetricPreferences: [MetricPreference]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CURRENT SPEED")
                        .font(.caption.weight(.black))
                        .tracking(1.2)
                        .foregroundStyle(WorkoutTheme.muted)
                    Text(String(format: "%.1f", treadmillData.speedKmh ?? 0))
                        .font(.system(size: 58, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(WorkoutTheme.paper)
                    Text("KM/H")
                        .font(.caption.weight(.black))
                        .tracking(1.5)
                        .foregroundStyle(WorkoutTheme.controlAccent)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Text(String(format: "%.1f", treadmillData.distanceKilometers))
                        .font(.title2.weight(.black))
                        .monospacedDigit()
                    Text("KM DISTANCE")
                        .font(.caption2.weight(.black))
                        .tracking(0.8)
                        .foregroundStyle(WorkoutTheme.muted)
                }
            }

            Divider().overlay(WorkoutTheme.paper.opacity(0.12))

            HStack(spacing: 0) {
                compactMetric(label: "PACE", value: treadmillData.paceMinPerKm.map { String(format: "%.1f", $0) } ?? "--", unit: "MIN/KM")
                compactMetric(label: "INCLINE", value: treadmillData.incline.map { String(format: "%.1f", $0) } ?? "--", unit: "%")
                compactMetric(label: "HEART", value: treadmillData.heartRate.map { String($0) } ?? "--", unit: "BPM")
            }

            let additionalMetrics = visibleMetricPreferences.filter { ![.speed, .distance, .pace, .incline, .heartRate].contains($0.id) }
            if !additionalMetrics.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(additionalMetrics) { preference in
                        if preference.id == .cadence {
                            compactMetric(label: "CADENCE", value: treadmillData.cadenceSpm.map { String($0) } ?? "--", unit: "SPM")
                        }
                    }
                }
            }
        }
        .padding()
        .background(WorkoutTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(WorkoutTheme.paper.opacity(0.08)))
        .panelNoise(cornerRadius: 16)
    }

    private func compactMetric(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.black))
                .tracking(0.8)
                .foregroundStyle(WorkoutTheme.muted)
            Text(value)
                .font(.headline.weight(.black))
                .monospacedDigit()
            Text(unit)
                .font(.caption2.weight(.medium))
                .foregroundStyle(WorkoutTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
