import Foundation
import SwiftUI

struct PlanFlowHeader: View {
    let isMinimized: Bool
    var body: some View {
        VStack(alignment: isMinimized ? .center : .leading, spacing: 8) {
            Text("BUILD THE PLAN").font(.system(size: isMinimized ? 36 : 30, weight: .black).italic())
                .shadow(radius: 1, x: 1, y: 1).foregroundStyle(WorkoutTheme.orange.gradient)
                .padding(.vertical, isMinimized ? 16 : 0)
            Text("Set speed, time, and repeats. Then follow the next move without thinking about the screen.")
                .font(.subheadline).foregroundStyle(WorkoutTheme.muted)
        }
    }
}

struct PlanCardHeader: View {
    @ObservedObject var viewModel: TrainingPlanViewModel
    let isRunning: Bool
    let isComplete: Bool
    let onSave: () -> Void
    let onShowSaved: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Training plan", systemImage: "figure.run.circle.fill").font(.headline)
                if isRunning { Text(viewModel.name).font(.title3.weight(.bold)) }
                else { TextField("Workout name", text: $viewModel.name).font(.title3.weight(.bold)).textFieldStyle(.plain) }
                Text("\(TrainingPlanCalculator.durationSummary(TrainingPlanCalculator.duration(of: viewModel.blocks))) · \(TrainingPlanCalculator.intervalCount(in: viewModel.blocks)) intervals")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if isRunning {
                Button(isComplete ? "Done" : "Stop", action: onStop).buttonStyle(.bordered)
            } else {
                HStack(spacing: 8) {
                    Button(action: onSave) { Image(systemName: "square.and.arrow.down").frame(width: 34, height: 34) }.accessibilityLabel("Save current plan")
                    Button(action: onShowSaved) { Image(systemName: "folder").frame(width: 34, height: 34) }.accessibilityLabel("Saved plans")
                }.font(.subheadline.weight(.semibold)).buttonStyle(.bordered).controlSize(.small)
            }
        }.padding(.horizontal, 14)
    }
}

struct CurrentStepView: View {
    let step: TrainingPlanStep
    let elapsed: TimeInterval
    @ObservedObject var runner: TrainingPlanRunner
    let planBlocks: [TrainingPlanBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "scope").foregroundStyle(WorkoutTheme.controlAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Now: \(step.title)").font(.subheadline.weight(.semibold))
                    Text("\(step.durationLabel) · \(String(format: "%.1f km/h", step.targetSpeedKmh))").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(timeLabel(max(0, step.durationSeconds - elapsedInStep))).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(12).background(WorkoutTheme.controlAccent.opacity(0.10)).clipShape(RoundedRectangle(cornerRadius: 12))
            HStack { Text("Stage progress").font(.caption.weight(.semibold)); Spacer(); Text("\(Int(runner.phaseProgress * 100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            ProgressView(value: runner.phaseProgress).tint(WorkoutTheme.controlAccent).animation(.linear(duration: 1), value: runner.phaseProgress)
            ProgressView(value: runner.workoutProgress).tint(WorkoutTheme.paper).animation(.linear(duration: 1), value: runner.workoutProgress)
        }.padding(.horizontal, 14)
    }

    private var elapsedInStep: TimeInterval { TrainingPlanCalculator.elapsedInCurrentStep(in: planBlocks, elapsed: elapsed) }
    private func timeLabel(_ seconds: TimeInterval) -> String { TrainingPlanCalculator.timeLabel(seconds) }
}

struct TrainingPlanBlockCard: View {
    @Binding var block: TrainingPlanBlock
    let onEdit: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: block.kind.icon).font(.headline).foregroundStyle(WorkoutTheme.controlAccent)
                .frame(width: 34, height: 34).background(WorkoutTheme.controlAccent.opacity(0.12)).clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(block.title).font(.headline)
                Text(block.summary).font(.caption).foregroundStyle(.secondary)
                if let recovery = block.recoverySummary { Text("+ \(recovery)").font(.caption2).foregroundStyle(WorkoutTheme.muted) }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(TrainingPlanCalculator.durationSummary(block.totalDuration)).font(.caption.monospacedDigit().bold()).foregroundStyle(.secondary)
                Button(action: onEdit) { Image(systemName: "slider.horizontal.3").font(.subheadline.weight(.bold)).frame(width: 32, height: 32) }
                    .buttonStyle(.borderless).foregroundStyle(WorkoutTheme.controlAccent)
            }.frame(minWidth: 68, alignment: .topTrailing)
        }
        .padding(14).background(WorkoutTheme.ink).clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.08))).contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct SavedTrainingPlansView: View {
    let plans: [TrainingPlanTemplate]
    let onSelect: (TrainingPlanTemplate) -> Void
    let onDelete: (TrainingPlanTemplate) -> Void
    let onDone: () -> Void
    var body: some View {
        NavigationStack {
            List {
                if plans.isEmpty { ContentUnavailableView("No saved plans", systemImage: "folder", description: Text("Save a plan to reuse it later.")) }
                else { ForEach(plans) { plan in
                    Button(action: { onSelect(plan) }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(plan.name).font(.headline)
                            Text("\(plan.blocks.count) blocks · \(TrainingPlanCalculator.durationSummary(plan.blocks.reduce(0) { $0 + $1.totalDuration }))").font(.caption).foregroundStyle(.secondary)
                            Text("Last updated \(plan.createdAt.formatted(date: .abbreviated, time: .omitted))").font(.caption2).foregroundStyle(.secondary)
                        }
                    }.swipeActions { Button(role: .destructive) { onDelete(plan) } label: { Label("Delete", systemImage: "trash") } }
                }}
            }.navigationTitle("Saved plans").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done", action: onDone) } }
        }
    }
}

struct TrainingPlanEditView: View {
    @Binding var block: TrainingPlanBlock
    let onDone: () -> Void
    var body: some View {
        NavigationStack {
            Form {
                if block.kind == .intervalGroup {
                    Section("Repeat as a group") {
                        Label("\(block.repetitions)×  Work + recovery", systemImage: block.kind.icon)
                        Stepper(value: $block.repetitions, in: 1...20) { Text("Repetitions: \(block.repetitions)").monospacedDigit() }
                        PlanDurationSpeedRow(title: "Work", duration: $block.durationSeconds, speed: $block.targetSpeedKmh)
                        PlanDurationSpeedRow(title: "Recovery", duration: $block.recoveryDurationSeconds, speed: $block.recoverySpeedKmh)
                    }
                } else {
                    Section("Step") {
                        Label(block.title, systemImage: block.kind.icon)
                        PlanDurationSpeedRow(title: "Duration", duration: $block.durationSeconds, speed: $block.targetSpeedKmh)
                    }
                }
            }.navigationTitle("Edit step").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done", action: onDone) } }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
}

struct PlanDurationSpeedRow: View {
    let title: String
    @Binding var duration: TimeInterval
    @Binding var speed: Double
    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(.subheadline.weight(.medium)).frame(width: 64, alignment: .leading)
            HStack(spacing: 6) {
                TextField("min", value: Binding(get: { duration / 60 }, set: { duration = max(0, $0 * 60) }), format: .number.precision(.fractionLength(0...1))).keyboardType(.decimalPad).multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder)
                Text("min").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                TextField("speed", value: $speed, format: .number.precision(.fractionLength(1))).keyboardType(.decimalPad).multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder)
                Text("km/h").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
