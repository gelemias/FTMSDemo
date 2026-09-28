import ActivityKit
import SwiftUI
import WidgetKit

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

struct TrainingPlanLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrainingPlanActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(context.attributes.workoutName, systemImage: "figure.run")
                        .font(.headline)
                    Spacer()
                    Text(context.state.isComplete ? "Done" : timeLabel(context.state.secondsRemaining))
                        .font(.headline.monospacedDigit())
                }
                Text(context.state.phaseTitle)
                    .font(.title3.bold())
                HStack {
                    Text(String(format: "%.1f km/h", context.state.targetSpeedKmh))
                    Spacer()
                    Text("Phase \(context.state.phaseNumber) of \(context.state.totalPhases)")
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: context.state.workoutProgress)
                    .tint(.blue)
            }
            .padding()
            .activityBackgroundTint(Color.blue.opacity(0.12))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "figure.run")
                        .foregroundStyle(.blue)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.state.phaseTitle)
                            .font(.headline)
                            .lineLimit(1)
                        Text(String(format: "%.1f km/h", context.state.targetSpeedKmh))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timeLabel(context.state.secondsRemaining))
                        .font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        ProgressView(value: context.state.phaseProgress)
                            .tint(.blue)
                        HStack {
                            Text("Phase \(context.state.phaseNumber)/\(context.state.totalPhases)")
                                .font(.caption)
                            Spacer()
                            Text("Total \(timeLabel(context.state.totalSecondsRemaining))")
                                .font(.caption.monospacedDigit())
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "figure.run")
                    .foregroundStyle(.blue)
            } compactTrailing: {
                Text(timeLabel(context.state.secondsRemaining))
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: "figure.run")
                    .foregroundStyle(.blue)
            }
            .widgetURL(URL(string: "ftmsdemo://training-plan"))
            .keylineTint(.blue)
        }
    }

    private func timeLabel(_ seconds: Int) -> String {
        String(format: "%02d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
    }
}

@main
struct FTMSDemoWidgets: WidgetBundle {
    var body: some Widget {
        TrainingPlanLiveActivity()
    }
}
