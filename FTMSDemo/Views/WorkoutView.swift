import SwiftUI

struct WorkoutView: View {
    @ObservedObject var connection: ConnectionViewModel
    @Binding var isWorkoutRunning: Bool
    @Binding var targetSpeedKmh: Double
    @Binding var customSpeedOne: Double
    @Binding var customSpeedTwo: Double
    @Binding var metricPreferences: [MetricPreference]

    let onAdjustSpeed: (Double) -> Void
    let onSetTargetSpeed: (Double) -> Void
    let onEditCustomSpeed: (Int) -> Void
    let onShowMetrics: () -> Void
    let onToggleWorkout: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                WorkoutStatusStripView(
                    isWorkoutRunning: isWorkoutRunning,
                    connectedDeviceName: connection.connectedDeviceName,
                    isLoading: connection.isLoading
                )
                PrimaryMetricCardView(
                    treadmillData: connection.treadmillData,
                    visibleMetricPreferences: metricPreferences.filter(\.isVisible)
                )
                WorkoutControlPanel(
                    targetSpeedKmh: $targetSpeedKmh,
                    customSpeedOne: $customSpeedOne,
                    customSpeedTwo: $customSpeedTwo,
                    isWorkoutRunning: isWorkoutRunning,
                    canControl: connection.controlPointReady,
                    onAdjustSpeed: onAdjustSpeed,
                    onSetTargetSpeed: onSetTargetSpeed,
                    onEditCustomSpeed: onEditCustomSpeed,
                    onShowMetrics: onShowMetrics,
                    onToggleWorkout: onToggleWorkout
                )
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .scrollContentBackground(.hidden)
        .safeAreaPadding(.bottom, 144)
        .navigationTitle("CONTROL")
    }
}
