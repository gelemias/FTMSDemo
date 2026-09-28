import SwiftUI

struct WorkoutControlPanel: View {
    @Binding var targetSpeedKmh: Double
    @Binding var customSpeedOne: Double
    @Binding var customSpeedTwo: Double
    let isWorkoutRunning: Bool
    let canControl: Bool
    let onAdjustSpeed: (Double) -> Void
    let onSetTargetSpeed: (Double) -> Void
    let onEditCustomSpeed: (Int) -> Void
    let onShowMetrics: () -> Void
    let onToggleWorkout: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("SET PACE")
                    .font(.caption.weight(.black))
                    .tracking(1.2)
                    .foregroundStyle(WorkoutTheme.muted)
                Spacer()
                Button(action: onShowMetrics) {
                    Label("Metrics", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.bold))
                }
                .tint(WorkoutTheme.muted)
            }

            HStack(spacing: 16) {
                stepButton(systemName: "minus") { onAdjustSpeed(-0.1) }

                VStack(spacing: 2) {
                    Text(String(format: "%.1f", targetSpeedKmh))
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .monospacedDigit()
                    Text("KM/H")
                        .font(.caption.weight(.black))
                        .tracking(1.5)
                        .foregroundStyle(WorkoutTheme.controlAccent)
                }
                .frame(maxWidth: .infinity)

                stepButton(systemName: "plus") { onAdjustSpeed(0.1) }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach([10.0, 12.0, 14.0, 16.0], id: \.self) { quickSpeed in
                    Button { onSetTargetSpeed(quickSpeed) } label: {
                        Text(String(format: "%.0f km/h", quickSpeed))
                            .font(.headline.weight(.black))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 64)
                            .background(targetSpeedKmh == quickSpeed ? WorkoutTheme.controlAccent : WorkoutTheme.panelRaised)
                            .foregroundStyle(targetSpeedKmh == quickSpeed ? WorkoutTheme.ink : WorkoutTheme.paper)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .panelNoise(cornerRadius: 12, enabled: targetSpeedKmh != quickSpeed)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canControl)
                }
                customShortcutTile(speed: customSpeedOne, slot: 1)
                customShortcutTile(speed: customSpeedTwo, slot: 2)
            }
        }
        .padding()
        .background(WorkoutTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .panelNoise(cornerRadius: 16)

        Button(action: onToggleWorkout) {
            Label(isWorkoutRunning ? "STOP WORKOUT" : "START WORKOUT", systemImage: isWorkoutRunning ? "stop.fill" : "play.fill")
                .font(.headline.weight(.black))
                .tracking(0.8)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 68)
        }
        .buttonStyle(.borderedProminent)
        .tint(WorkoutTheme.controlAccent)
        .foregroundStyle(WorkoutTheme.ink)
        .controlSize(.large)
        .disabled(!canControl)
    }

    private func stepButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title.weight(.black))
                .frame(width: 76, height: 76)
                .background(WorkoutTheme.panelRaised)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .panelNoise(cornerRadius: 14)
        }
        .buttonStyle(.plain)
        .disabled(!canControl)
    }

    private func customShortcutTile(speed: Double, slot: Int) -> some View {
        HStack(spacing: 8) {
            Button { onSetTargetSpeed(speed) } label: {
                Text(String(format: "%.1f km/h", speed))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 72)
                    .foregroundStyle(targetSpeedKmh == speed ? WorkoutTheme.ink : WorkoutTheme.paper)
            }
            .buttonStyle(.plain)
            .disabled(!canControl)

            Button { onEditCustomSpeed(slot) } label: {
                Image(systemName: "pencil")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .background(targetSpeedKmh == speed ? WorkoutTheme.controlAccent : WorkoutTheme.panelRaised)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .panelNoise(cornerRadius: 12, enabled: targetSpeedKmh != speed)
    }
}
