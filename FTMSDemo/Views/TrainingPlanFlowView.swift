import Foundation
import SwiftUI

/// Owns the training-plan editor and runner presentation. Keeping this flow isolated
/// prevents plan editing state from invalidating the live workout dashboard.
struct TrainingPlanFlowView: View {
    @ObservedObject var connection: ConnectionViewModel
    @ObservedObject var viewModel: TrainingPlanViewModel
    @ObservedObject var runner: TrainingPlanRunner
    @Binding var startedAt: Date?
    @Binding var detent: PresentationDetent

    let onStart: () -> Void
    let onStop: () -> Void
    let onSetTargetSpeed: (Double) -> Void
    let onToast: (String) -> Void

    @State private var editingBlockID: UUID?
    @State private var swipedBlockID: UUID?
    @State private var showingSavedPlans = false
    @State private var duplicatePlan: TrainingPlanTemplate?
    @State private var showingDuplicateAlert = false
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var pressedBlockID: UUID?
    @State private var draggedBlockID: UUID?
    @State private var didMoveBlock = false

    var body: some View {
        GeometryReader { viewport in
            let minimized = detent == .height(80)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PlanFlowHeader(isMinimized: minimized)
                    planCard(maxEditorHeight: max(240, viewport.size.height - 250))
                    if startedAt == nil {
                        Button(action: onStart) {
                            Label(connection.controlPointReady ? "Start workout" : "Connect to start",
                                  systemImage: connection.controlPointReady ? "play.fill" : "lock.fill")
                                .font(.headline.weight(.bold)).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(WorkoutTheme.orange.gradient)
                        .foregroundStyle(WorkoutTheme.primaryButtonForeground).controlSize(.large)
                        .disabled(!connection.controlPointReady)
                    }
                }
                .padding(.horizontal).padding(.vertical, minimized ? 8 : 16)
            }
        }
        .scrollContentBackground(.hidden).scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(TapGesture().onEnded {
            dismissKeyboard()
            guard detent == .height(80) else { return }
            withAnimation(.snappy) { detent = .large }
        })
        .navigationTitle("PLAN")
    }

    private func planCard(maxEditorHeight: CGFloat) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = startedAt.map { max(0, context.date.timeIntervalSince($0)) } ?? 0
            let currentStep = TrainingPlanCalculator.currentStep(in: viewModel.blocks, elapsed: elapsed, isRunning: startedAt != nil)
            let complete = startedAt != nil && currentStep == nil

            VStack(alignment: .leading, spacing: 14) {
                PlanCardHeader(viewModel: viewModel, isRunning: startedAt != nil,
                               isComplete: complete, onSave: savePlan,
                               onShowSaved: { showingSavedPlans = true }, onStop: onStop)
                if let currentStep, startedAt != nil {
                    CurrentStepView(step: currentStep, elapsed: elapsed, runner: runner,
                                    planBlocks: viewModel.blocks)
                } else if complete {
                    Label("Nice work — all steps are complete.", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(WorkoutTheme.controlAccent)
                        .padding(.horizontal, 14)
                }
                if startedAt == nil { editor }
            }
            .padding(.vertical, 14).background(WorkoutTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 18)).panelNoise(cornerRadius: 18)
            .onChange(of: currentStep?.title) { _, _ in
                guard let currentStep, startedAt != nil else { return }
                onSetTargetSpeed(currentStep.targetSpeedKmh)
            }
        }
        .sheet(isPresented: $showingSavedPlans) { savedPlansSheet }
        .sheet(item: Binding(get: {
            editingBlockID.flatMap { id in viewModel.blocks.first { $0.id == id } }
        }, set: { editingBlockID = $0?.id })) { block in
            if let index = viewModel.blocks.firstIndex(where: { $0.id == block.id }) {
                TrainingPlanEditView(block: $viewModel.blocks[index], onDone: { editingBlockID = nil })
            }
        }
        .alert("Plan already exists", isPresented: $showingDuplicateAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Update existing") {
                if let duplicatePlan { viewModel.updateNamedPlan(duplicatePlan); onToast("Plan \"\(viewModel.name)\" updated.") }
            }
        } message: {
            Text("A plan named \"\(viewModel.name)\" is already saved. Do you want to replace it with the current plan?")
        }
    }

    @ViewBuilder
    private var editor: some View {
        VStack(spacing: 10) {
            ForEach($viewModel.blocks) { $block in row(block: $block) }
        }
        .coordinateSpace(name: "trainingPlanEditor")
        .onPreferenceChange(TrainingPlanRowFramePreferenceKey.self) { rowFrames = $0 }
        Menu {
            Button { addBlock(.intervalGroup) } label: { Label("Interval group", systemImage: "repeat") }
            Button { addBlock(.steadyRun) } label: { Label("Regular run", systemImage: "figure.run") }
        } label: {
            Image(systemName: "plus").font(.title3.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 44).background(WorkoutTheme.ink)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay { RoundedRectangle(cornerRadius: 16).stroke(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])) }
        }
        .tint(WorkoutTheme.controlAccent).opacity(0.75).accessibilityLabel("Add step")
        .padding(.horizontal, 14)
    }

    private func row(block: Binding<TrainingPlanBlock>) -> some View {
        let id = block.wrappedValue.id
        return ZStack(alignment: .trailing) {
            if swipedBlockID == id {
                Button(role: .destructive) { viewModel.blocks.removeAll { $0.id == id }; swipedBlockID = nil } label: {
                    Image(systemName: "trash").foregroundStyle(.white).frame(maxHeight: .infinity).frame(width: 76)
                }.background(Color.red).clipShape(RoundedRectangle(cornerRadius: 16)).padding(.horizontal, 14)
            }
            TrainingPlanBlockCard(block: block, onEdit: { editingBlockID = id })
                .padding(.horizontal, 14).offset(x: swipedBlockID == id ? -76 : 0)
                .scaleEffect(pressedBlockID == id ? 1.05 : 1).zIndex(draggedBlockID == id ? 1 : 0)
                .animation(.snappy(duration: 0.18), value: pressedBlockID)
                .simultaneousGesture(DragGesture(minimumDistance: 18).onEnded { value in
                    if value.translation.width < -40 { withAnimation(.snappy) { swipedBlockID = id } }
                    else if value.translation.width > 20 { withAnimation(.snappy) { swipedBlockID = nil } }
                })
                .simultaneousGesture(reorderGesture(for: id))
                .background { GeometryReader { proxy in
                    Color.clear.preference(key: TrainingPlanRowFramePreferenceKey.self,
                                           value: [id: proxy.frame(in: .named("trainingPlanEditor"))])
                }}
        }.animation(.snappy, value: swipedBlockID)
    }

    private func reorderGesture(for id: UUID) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("trainingPlanEditor")))
            .onChanged { value in
                switch value {
                case .first(true): draggedBlockID = id; didMoveBlock = false
                case .second(true, let drag?):
                    guard abs(drag.translation.width) > 4 || abs(drag.translation.height) > 4 else { return }
                    didMoveBlock = true; reorder(at: drag.location.y)
                default: break
                }
            }
            .onEnded { _ in draggedBlockID = nil; didMoveBlock = false }
    }

    private func reorder(at y: CGFloat) {
        guard let draggedBlockID, let from = viewModel.blocks.firstIndex(where: { $0.id == draggedBlockID }) else { return }
        let destination: Int
        if let down = viewModel.blocks.indices.reversed().first(where: { index in
            index > from && y > (rowFrames[viewModel.blocks[index].id]?.midY ?? .infinity)
        }) { destination = down + 1
        } else if let up = viewModel.blocks.indices.first(where: { index in
            index < from && y < (rowFrames[viewModel.blocks[index].id]?.midY ?? -.infinity)
        }) { destination = up
        } else { destination = from }
        guard destination != from else { return }
        withAnimation(.snappy(duration: 0.22)) { viewModel.blocks.move(fromOffsets: IndexSet(integer: from), toOffset: destination) }
    }

    private func addBlock(_ kind: TrainingPlanBlockKind) {
        let block = TrainingPlanBlock(kind: kind, durationSeconds: kind == .intervalGroup ? 180 : 300,
                                      targetSpeedKmh: kind == .intervalGroup ? 14 : 10,
                                      repetitions: kind == .intervalGroup ? 4 : 1,
                                      recoveryDurationSeconds: kind == .intervalGroup ? 60 : 0,
                                      recoverySpeedKmh: kind == .intervalGroup ? 9 : 0)
        viewModel.blocks.insert(block, at: max(0, viewModel.blocks.count - 1))
    }

    private var savedPlansSheet: some View {
        SavedTrainingPlansView(plans: viewModel.savedPlans,
                               onSelect: { plan in viewModel.name = plan.name; viewModel.blocks = plan.blocks; showingSavedPlans = false; onToast("Plan \"\(plan.name)\" loaded.") },
                               onDelete: viewModel.deletePlan,
                               onDone: { showingSavedPlans = false })
    }

    private func savePlan() {
        let name = viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Training plan" : viewModel.name
        viewModel.name = name
        switch viewModel.saveNamedPlan() {
        case .saved: onToast("Plan \"\(name)\" saved.")
        case .duplicate(let plan): duplicatePlan = plan; showingDuplicateAlert = true
        case nil: break
        }
    }

    private func dismissKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}
