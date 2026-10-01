//
//  ContentView.swift
//  FTMSDemo
//
//  Created by DELGADO Guillermo on 15/11/25.
//

import Foundation
import Combine
import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var connectionViewModel = ConnectionViewModel()
    @StateObject private var workoutViewModel = WorkoutViewModel()
    @StateObject private var trainingPlanViewModel = TrainingPlanViewModel()
    @StateObject private var trainingPlanRunner = TrainingPlanRunner()
    @Environment(\.scenePhase) private var scenePhase
    private let preferencesStore = WorkoutPreferencesStore()
    @State private var showCustomSpeedAlert = false
    @State private var editingCustomSlot = 1
    @State private var customSpeedInput = ""
    @State private var metricPreferences: [MetricPreference] = WorkoutPreferencesStore.defaultMetricPreferences
    @State private var showMetricCustomization = false
    @State private var didLoadMetricPreferences = false
    @State private var showingSavedPlans = false
    @State private var duplicatePlan: TrainingPlanTemplate?
    @State private var showingDuplicatePlanAlert = false
    @State private var editingBlockID: UUID?
    @State private var pressedBlockID: UUID?
    @State private var draggedBlockID: UUID?
    @State private var didMoveTrainingPlanBlock = false
    @State private var trainingPlanRowFrames: [UUID: CGRect] = [:]
    @State private var swipedBlockID: UUID?
    @State private var didLoadTrainingPlan = false
    @State private var trainingPlanStartedAt: Date?
    @State private var showTrainingFlow = true
    @State private var trainingFlowDetent: PresentationDetent = .height(80)
    @StateObject private var toastWindowManager = StatusToastWindowManager()

    private var ftms: ConnectionViewModel { connectionViewModel }
    private var targetSpeedKmh: Double {
        get { workoutViewModel.targetSpeedKmh }
        set { workoutViewModel.targetSpeedKmh = newValue }
    }
    private var customSpeedOne: Double {
        get { workoutViewModel.customSpeedOne }
        set { workoutViewModel.customSpeedOne = newValue }
    }
    private var customSpeedTwo: Double {
        get { workoutViewModel.customSpeedTwo }
        set { workoutViewModel.customSpeedTwo = newValue }
    }
    private var isWorkoutRunning: Bool {
        get { workoutViewModel.isWorkoutRunning }
        set { workoutViewModel.isWorkoutRunning = newValue }
    }
    private var trainingPlanBlocks: [TrainingPlanBlock] {
        get { trainingPlanViewModel.blocks }
        set { trainingPlanViewModel.blocks = newValue }
    }
    private var trainingPlanName: String {
        get { trainingPlanViewModel.name }
        set { trainingPlanViewModel.name = newValue }
    }
    private var savedTrainingPlans: [TrainingPlanTemplate] {
        trainingPlanViewModel.savedPlans
    }

    var body: some View {
        ZStack(alignment: .top) {
            WorkoutTheme.ink
                .ignoresSafeArea()

            NavigationStack {
                Group {
                    if ftms.isConnected {
                        connectedDashboard
                    } else {
                        disconnectedWorkspace
                    }
                }
                .background(Color.clear)
                .onChange(of: ftms.isConnected) { _, isConnected in
                    guard !isConnected else { return }
                    trainingPlanRunner.stop()
                workoutViewModel.isWorkoutRunning = false
                    trainingPlanStartedAt = nil
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if ftms.isConnected {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                toggleWorkoutState()
                            } label: {
                                Label(isWorkoutRunning ? "Stop" : "Run", systemImage: isWorkoutRunning ? "stop.fill" : "play.fill")
                            }
                            .tint(WorkoutTheme.controlAccent)
                            .disabled(!ftms.controlPointReady)
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                ftms.disconnect()
                workoutViewModel.isWorkoutRunning = false
                            } label: {
                                Label("Disconnect", systemImage: "bolt.slash")
                            }
                            .tint(WorkoutTheme.paper)
                        }
                    }
                }
                .sheet(isPresented: $showTrainingFlow) {
                    trainingFlowSheet
                        .presentationDetents([.height(80), .large], selection: $trainingFlowDetent)
                        .presentationDragIndicator(.visible)
                        .presentationBackground {
                            ZStack {
                                WorkoutTheme.panel
                                NoiseTexture()
                            }
                        }
                        .presentationBackgroundInteraction(.enabled(upThrough: .large))
                        .interactiveDismissDisabled(true)
                }
                .tint(WorkoutTheme.controlAccent)
                .background {
                    ZStack {
                        WorkoutTheme.ink
                        RubberFloorTexture()
                            .opacity(0.7)
                    }
                    .ignoresSafeArea()
                }
            }

        }
        .onAppear {
            presentStatusToast(ftms.statusMessage)
        }
        .onChange(of: ftms.statusMessage) { _, newMessage in
            presentStatusToast(newMessage)
        }
    }

    private var disconnectedWorkspace: some View {
        ConnectionView(viewModel: ftms)
    }

    private var connectedDashboard: some View {
        controlDashboard
        .onAppear {
            loadTrainingPlanIfNeeded()
        }
    }

    private var trainingFlowSheet: some View {
        trainingPlanDashboard
            .onAppear {
                loadTrainingPlanIfNeeded()
            }
    }

    private var controlDashboard: some View {
        WorkoutView(
            connection: connectionViewModel,
            isWorkoutRunning: $workoutViewModel.isWorkoutRunning,
            targetSpeedKmh: $workoutViewModel.targetSpeedKmh,
            customSpeedOne: $workoutViewModel.customSpeedOne,
            customSpeedTwo: $workoutViewModel.customSpeedTwo,
            metricPreferences: $metricPreferences,
            onAdjustSpeed: adjustSpeed,
            onSetTargetSpeed: setTargetSpeed,
            onEditCustomSpeed: openEditCustomSpeed,
            onShowMetrics: { showMetricCustomization = true },
            onToggleWorkout: toggleWorkoutState
        )
        .onChange(of: ftms.treadmillData.speedKmh) { _, newValue in
            guard let newValue else { return }
            if abs(newValue - targetSpeedKmh) > 0.2 {
                workoutViewModel.targetSpeedKmh = (newValue * 10).rounded() / 10
            }
        }
        .onChange(of: ftms.isConnected) { _, isConnected in
            if !isConnected {
                    workoutViewModel.isWorkoutRunning = false
                trainingPlanStartedAt = nil
                trainingPlanRunner.stop()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                trainingPlanRunner.refresh()
            }
        }
        .onChange(of: metricPreferences) { _, _ in
            saveMetricPreferences()
        }
        .onChange(of: trainingPlanBlocks) { _, _ in
            saveTrainingPlan()
        }
        .onAppear {
            loadMetricPreferencesIfNeeded()
        }
        .alert("Edit custom speed", isPresented: $showCustomSpeedAlert) {
            TextField("km/h", text: customSpeedInputBinding)
                .keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                saveCustomSpeed()
            }
            .disabled(!isCustomSpeedInputValid)
        } message: {
            Text("Enter a number between 0.1 and 22.0 km/h.")
        }
        .sheet(isPresented: $showMetricCustomization) {
            MetricCustomizationView(
                preferences: $metricPreferences,
                onMove: moveMetric,
                onDone: { showMetricCustomization = false }
            )
        }
    }

    private var trainingPlanDashboard: some View {
        GeometryReader { viewport in
            let isTrainingFlowMinimized = trainingFlowDetent == .height(80)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: isTrainingFlowMinimized ? .center : .leading, spacing: 8) {
                        Text("BUILD THE PLAN")
                            .font(.system(size: isTrainingFlowMinimized ? 36 : 30, weight: .black).italic())
                            .shadow(radius: 1.0, x: 1.0, y: 1.0)
                            .foregroundStyle(WorkoutTheme.orange.gradient)
                            .padding( .vertical, isTrainingFlowMinimized ? 16 : 0)
                            Text("Set speed, time, and repeats. Then follow the next move without thinking about the screen.")
                                .font(.subheadline)
                                .foregroundStyle(WorkoutTheme.muted)
                    }

                    trainingPlanCard(maxEditorHeight: max(240, viewport.size.height - 250))

                    if trainingPlanStartedAt == nil {
                        Button {
                            guard ftms.controlPointReady else { return }
                            startTrainingPlan()
                        } label: {
                            Label(ftms.controlPointReady ? "Start workout" : "Connect to start", systemImage: ftms.controlPointReady ? "play.fill" : "lock.fill")
                                .font(.headline.weight(.bold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(WorkoutTheme.orange.gradient)
                        .foregroundStyle(WorkoutTheme.primaryButtonForeground)
                        .controlSize(.large)
                        .disabled(!ftms.controlPointReady)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, isTrainingFlowMinimized ? 8 : 16)
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(TapGesture().onEnded {
            dismissKeyboard()
            guard trainingFlowDetent == .height(80) else { return }
            withAnimation(.snappy) {
                trainingFlowDetent = .large
            }
        })
        .navigationTitle("PLAN")
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func setTargetSpeed(_ speed: Double) {
        let normalized = workoutViewModel.setTargetSpeed(speed)
        ftms.sendTargetSpeed(kmh: normalized)
    }

    private func adjustSpeed(by delta: Double) {
        let normalized = workoutViewModel.adjustSpeed(by: delta)
        ftms.sendTargetSpeed(kmh: normalized)
    }

    private func toggleWorkoutState() {
        if isWorkoutRunning {
            if trainingPlanStartedAt != nil {
                stopTrainingPlan()
            } else {
                ftms.stopTreadmill()
                                workoutViewModel.isWorkoutRunning = false
            }
        } else {
            ftms.startTreadmill()
            workoutViewModel.isWorkoutRunning = true
        }
    }

    private func startTrainingPlan() {
        guard ftms.controlPointReady else { return }
        trainingPlanStartedAt = Date()
        trainingPlanRunner.start(
            blocks: trainingPlanBlocks,
            workoutName: trainingPlanName,
            treadmillName: ftms.connectedDeviceName ?? "Treadmill",
            actions: TrainingPlanRunnerActions(
                sendSpeed: { speed in ftms.sendTargetSpeed(kmh: speed) },
                startTreadmill: { ftms.startTreadmill() },
                stopTreadmill: { ftms.stopTreadmill() }
            )
        )
        workoutViewModel.isWorkoutRunning = true
    }

    private func stopTrainingPlan() {
        trainingPlanRunner.stop()
        workoutViewModel.isWorkoutRunning = false
        trainingPlanStartedAt = nil
    }

    private func trainingPlanCard(maxEditorHeight: CGFloat) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = trainingPlanStartedAt.map { max(0, context.date.timeIntervalSince($0)) } ?? 0
            let currentStep = currentTrainingStep(for: elapsed)
            let isComplete = trainingPlanStartedAt != nil && currentStep == nil
            let editorListHeight = trainingPlanBlocks.reduce(CGFloat(0)) { total, block in
                total + (block.recoverySummary == nil ? 86 : 102)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Training plan", systemImage: "figure.run.circle.fill")
                            .font(.headline)
                        if trainingPlanStartedAt == nil {
                            TextField("Workout name", text: $trainingPlanViewModel.name)
                                .font(.title3.weight(.bold))
                                .textFieldStyle(.plain)
                        } else {
                            Text(trainingPlanName)
                                .font(.title3.weight(.bold))
                        }
                        Text("\(durationSummary(trainingPlanDuration)) · \(intervalCount) intervals")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if trainingPlanStartedAt == nil {
                        HStack(spacing: 8) {
                            Button { saveNamedTrainingPlan() } label: {
                                Image(systemName: "square.and.arrow.down")
                                    .frame(width: 34, height: 34)
                            }
                            .accessibilityLabel("Save current plan")

                            Button { showingSavedPlans = true } label: {
                                Image(systemName: "folder")
                                    .frame(width: 34, height: 34)
                            }
                            .accessibilityLabel("Saved plans")
                        }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Button(isComplete ? "Done" : "Stop") { stopTrainingPlan() }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, 14)

                if trainingPlanStartedAt != nil, let currentStep {
                    HStack(spacing: 10) {
                        Image(systemName: "scope")
                            .foregroundStyle(WorkoutTheme.controlAccent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Now: \(currentStep.title)")
                                .font(.subheadline.weight(.semibold))
                            Text("\(currentStep.durationLabel) · \(speedLabel(currentStep.targetSpeedKmh))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if trainingPlanStartedAt != nil {
                            Text(timeLabel(for: max(0, currentStep.durationSeconds - timeIntoCurrentStep(elapsed))))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .background(WorkoutTheme.controlAccent.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 14)
                    if trainingPlanStartedAt != nil {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("Stage progress").font(.caption.weight(.semibold))
                                Spacer()
                                Text("\(Int(trainingPlanRunner.phaseProgress * 100))%")
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            ProgressView(value: trainingPlanRunner.phaseProgress)
                                .tint(WorkoutTheme.controlAccent)
                                .animation(.linear(duration: 1), value: trainingPlanRunner.phaseProgress)
                            ProgressView(value: trainingPlanRunner.workoutProgress)
                                .tint(WorkoutTheme.paper)
                                .animation(.linear(duration: 1), value: trainingPlanRunner.workoutProgress)
                        }
                        .padding(.horizontal, 14)
                    }
                } else if isComplete {
                    Label("Nice work — all steps are complete.", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WorkoutTheme.controlAccent)
                        .padding(.horizontal, 14)
                }

                if trainingPlanStartedAt == nil {
                        VStack(spacing: 10) {
                        ForEach($trainingPlanViewModel.blocks) { $block in
                            trainingPlanBlockRow(block: $block)
                        }
                        }
                        .coordinateSpace(name: "trainingPlanEditor")
                        .onPreferenceChange(TrainingPlanRowFramePreferenceKey.self) { frames in
                            trainingPlanRowFrames = frames
                        }


                    Menu {
                        Button { addTrainingPlanBlock(.intervalGroup) } label: {
                            Label("Interval group", systemImage: "repeat")
                        }
                        Button { addTrainingPlanBlock(.steadyRun) } label: {
                            Label("Regular run", systemImage: "figure.run")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(WorkoutTheme.ink)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(
                                        style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                                    )
                            }
                    }
                    .tint(WorkoutTheme.controlAccent).opacity(0.75)
                    .accessibilityLabel("Add step")
                    .padding(.horizontal, 14)
                }
            }
            .padding(.vertical, 14)
            .background(WorkoutTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .panelNoise(cornerRadius: 18)
            .onChange(of: currentStep?.title) { _, _ in
                guard trainingPlanStartedAt != nil,
                      let currentStep else { return }
                setTargetSpeed(currentStep.targetSpeedKmh)
            }
            .sheet(isPresented: $showingSavedPlans) { savedPlansSheet }
            .sheet(item: Binding(get: {
                editingBlockID.flatMap { id in trainingPlanBlocks.first(where: { $0.id == id }) }
            }, set: { value in
                editingBlockID = value?.id
            })) { block in
                if let index = trainingPlanBlocks.firstIndex(where: { $0.id == block.id }) {
                    trainingPlanEditSheet(block: $trainingPlanViewModel.blocks[index])
                }
            }
            .alert("Plan already exists", isPresented: $showingDuplicatePlanAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Update existing") {
                    guard let duplicatePlan else { return }
                    trainingPlanViewModel.updateNamedPlan(duplicatePlan)
                    presentStatusToast("Plan \"\(trainingPlanName)\" updated.")
                }
            } message: {
                Text("A plan named \"\(trainingPlanName)\" is already saved. Do you want to replace it with the current plan?")
            }
        }
    }

    private func trainingPlanBlockEditor(block: Binding<TrainingPlanBlock>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: block.wrappedValue.kind.icon)
                    .font(.headline)
                    .foregroundStyle(WorkoutTheme.controlAccent)
                    .frame(width: 34, height: 34)
                    .background(WorkoutTheme.controlAccent.opacity(0.12))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(block.wrappedValue.title)
                        .font(.headline)
                    Text(block.wrappedValue.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let recoverySummary = block.wrappedValue.recoverySummary {
                        Text("+ \(recoverySummary)")
                            .font(.caption2)
                            .foregroundStyle(WorkoutTheme.muted)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(durationSummary(block.wrappedValue.totalDuration))
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(.secondary)
                    Button { editingBlockID = block.wrappedValue.id } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.subheadline.weight(.bold))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(WorkoutTheme.controlAccent)
                }
                .frame(minWidth: 68, alignment: .topTrailing)
            }
        }
        .padding(14)
        .background(WorkoutTheme.ink)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.08)))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func trainingPlanBlockRow(block: Binding<TrainingPlanBlock>) -> some View {
        let blockID = block.wrappedValue.id
        ZStack(alignment: .trailing) {
            if swipedBlockID == blockID {
                Button(role: .destructive) {
                    trainingPlanViewModel.blocks.removeAll { $0.id == blockID }
                    swipedBlockID = nil
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.white)
                        .frame(maxHeight: .infinity)
                        .frame(width: 76)
                }
                .background(Color.red)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 14)
            }

            trainingPlanBlockEditor(block: block)
                .padding(.horizontal, 14)
                .offset(x: swipedBlockID == blockID ? -76 : 0)
                .scaleEffect(pressedBlockID == blockID ? 1.05 : 1)
                .zIndex(draggedBlockID == blockID ? 1 : 0)
                .animation(.snappy(duration: 0.18), value: pressedBlockID)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if pressedBlockID != blockID {
                                pressedBlockID = blockID
                            }
                        }
                        .onEnded { _ in
                            guard pressedBlockID == blockID else { return }
                            withAnimation(.snappy(duration: 0.18)) {
                                pressedBlockID = nil
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 18)
                        .onEnded { value in
                            if value.translation.width < -40 {
                                withAnimation(.snappy) { swipedBlockID = blockID }
                            } else if value.translation.width > 20 {
                                withAnimation(.snappy) { swipedBlockID = nil }
                            }
                        }
                )
                .simultaneousGesture(trainingPlanReorderGesture(for: blockID))
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TrainingPlanRowFramePreferenceKey.self,
                            value: [blockID: proxy.frame(in: .named("trainingPlanEditor"))]
                        )
                    }
                }
        }
        .animation(.snappy, value: swipedBlockID)
    }

    private func trainingPlanReorderGesture(for blockID: UUID) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("trainingPlanEditor")))
            .onChanged { value in
                switch value {
                case .first(true):
                    draggedBlockID = blockID
                    didMoveTrainingPlanBlock = false
                case .second(true, let drag?):
                    let hasMoved = abs(drag.translation.width) > 4 || abs(drag.translation.height) > 4
                    guard hasMoved else { return }
                    didMoveTrainingPlanBlock = true
                    reorderTrainingPlanBlock(at: drag.location.y)
                default:
                    break
                }
            }
            .onEnded { _ in
                guard draggedBlockID == blockID else { return }
                if didMoveTrainingPlanBlock {
                    withAnimation(.snappy) {
                        draggedBlockID = nil
                    }
                } else {
                    draggedBlockID = nil
                }
                didMoveTrainingPlanBlock = false
            }
    }

    private func reorderTrainingPlanBlock(at verticalPosition: CGFloat) {
        guard let draggedBlockID,
              let fromIndex = trainingPlanBlocks.firstIndex(where: { $0.id == draggedBlockID }) else { return }

        let destination: Int

        if let downwardTarget = trainingPlanBlocks.indices.reversed().first(where: { index in
            guard index > fromIndex,
                  let frame = trainingPlanRowFrames[trainingPlanBlocks[index].id] else { return false }
            return verticalPosition > frame.midY
        }) {
            destination = downwardTarget + 1
        } else if let upwardTarget = trainingPlanBlocks.indices.first(where: { index in
            guard index < fromIndex,
                  let frame = trainingPlanRowFrames[trainingPlanBlocks[index].id] else { return false }
            return verticalPosition < frame.midY
        }) {
            destination = upwardTarget
        } else {
            destination = fromIndex
        }

        guard destination != fromIndex else { return }

        withAnimation(.snappy(duration: 0.22)) {
            trainingPlanViewModel.blocks.move(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: destination
            )
        }
    }

    private func planDurationSpeedRow(title: String, durationBinding: Binding<TimeInterval>, speedBinding: Binding<Double>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .frame(width: 64, alignment: .leading)
            HStack(spacing: 6) {
                TextField("min", value: Binding(get: { durationBinding.wrappedValue / 60 }, set: { durationBinding.wrappedValue = max(0, $0 * 60) }), format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                Text("min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                TextField("speed", value: speedBinding, format: .number.precision(.fractionLength(1)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                Text("km/h")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func addTrainingPlanBlock(_ kind: TrainingPlanBlockKind) {
        let block = TrainingPlanBlock(
            kind: kind,
            durationSeconds: kind == .intervalGroup ? 3 * 60 : 5 * 60,
            targetSpeedKmh: kind == .intervalGroup ? 14 : 10,
            repetitions: kind == .intervalGroup ? 4 : 1,
            recoveryDurationSeconds: kind == .intervalGroup ? 60 : 0,
            recoverySpeedKmh: kind == .intervalGroup ? 9 : 0
        )
        trainingPlanViewModel.blocks.insert(block, at: max(0, trainingPlanViewModel.blocks.count - 1))
    }

    private func moveTrainingPlanBlocks(from source: IndexSet, to destination: Int) {
        trainingPlanViewModel.blocks.move(fromOffsets: source, toOffset: destination)
    }

    private func trainingPlanEditSheet(block: Binding<TrainingPlanBlock>) -> some View {
        NavigationStack {
            Form {
                if block.wrappedValue.kind == .intervalGroup {
                    Section("Repeat as a group") {
                        HStack(spacing: 12) {
                            Text("\(block.wrappedValue.repetitions)×")
                                .font(.title2.weight(.black).monospacedDigit())
                                .foregroundStyle(WorkoutTheme.controlAccent)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Work + recovery")
                                    .font(.headline)
                                Text("The complete block repeats together")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Stepper(value: block.repetitions, in: 1...20) {
                            Text("Repetitions: \(block.wrappedValue.repetitions)")
                                .monospacedDigit()
                        }
                        planDurationSpeedRow(title: "Work", durationBinding: block.durationSeconds, speedBinding: block.targetSpeedKmh)
                        planDurationSpeedRow(title: "Recovery", durationBinding: block.recoveryDurationSeconds, speedBinding: block.recoverySpeedKmh)
                    }
                } else {
                    Section("Step") {
                        Label(block.wrappedValue.title, systemImage: block.wrappedValue.kind.icon)
                        planDurationSpeedRow(title: "Duration", durationBinding: block.durationSeconds, speedBinding: block.targetSpeedKmh)
                    }
                }
            }
            .navigationTitle("Edit step")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { editingBlockID = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var savedPlansSheet: some View {
        NavigationStack {
            List {
                if savedTrainingPlans.isEmpty {
                    ContentUnavailableView("No saved plans", systemImage: "folder", description: Text("Save a plan to reuse it later."))
                } else {
                    ForEach(savedTrainingPlans) { plan in
                        Button {
                            trainingPlanViewModel.name = plan.name
                            trainingPlanViewModel.blocks = plan.blocks
                            showingSavedPlans = false
                            presentStatusToast("Plan \"\(plan.name)\" loaded.")
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(plan.name).font(.headline)
                                Text("\(plan.blocks.count) blocks · \(durationSummary(plan.blocks.reduce(0) { $0 + $1.totalDuration }))")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("Last updated \(plan.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) { deleteSavedPlan(plan) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
            }
            .navigationTitle("Saved plans")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showingSavedPlans = false } } }
        }
    }

    private func saveNamedTrainingPlan() {
        let name = trainingPlanName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Training plan" : trainingPlanName
        trainingPlanViewModel.name = name
        switch trainingPlanViewModel.saveNamedPlan() {
        case .saved:
            presentStatusToast("Plan \"\(name)\" saved.")
        case .duplicate(let plan):
            duplicatePlan = plan
            showingDuplicatePlanAlert = true
        case nil:
            break
        }
    }

    private func deleteSavedPlan(_ plan: TrainingPlanTemplate) {
        trainingPlanViewModel.deletePlan(plan)
    }

    private func currentTrainingStep(for elapsed: TimeInterval) -> TrainingPlanStep? {
        TrainingPlanCalculator.currentStep(
            in: trainingPlanBlocks,
            elapsed: elapsed,
            isRunning: trainingPlanStartedAt != nil
        )
    }

    private var trainingPlanSteps: [TrainingPlanStep] {
        TrainingPlanCalculator.steps(from: trainingPlanBlocks)
    }

    private var trainingPlanDuration: TimeInterval {
        TrainingPlanCalculator.duration(of: trainingPlanBlocks)
    }

    private var intervalCount: Int {
        TrainingPlanCalculator.intervalCount(in: trainingPlanBlocks)
    }

    private func durationSummary(_ seconds: TimeInterval) -> String {
        TrainingPlanCalculator.durationSummary(seconds)
    }

    private func timeIntoCurrentStep(_ elapsed: TimeInterval) -> TimeInterval {
        TrainingPlanCalculator.elapsedInCurrentStep(in: trainingPlanBlocks, elapsed: elapsed)
    }

    private func timeLabel(for seconds: TimeInterval) -> String {
        TrainingPlanCalculator.timeLabel(seconds)
    }

    private func speedLabel(_ speed: Double) -> String {
        String(format: "%.1f km/h", speed)
    }

    private func loadTrainingPlanIfNeeded() {
        guard !didLoadTrainingPlan else { return }
        didLoadTrainingPlan = true

        trainingPlanViewModel.loadIfNeeded()
    }

    private func saveTrainingPlan() {
        trainingPlanViewModel.saveBlocks()
    }

    private func paceForSpeed(_ speedKmh: Double) -> Double {
        guard speedKmh > 0 else { return 0 }
        return 60.0 / speedKmh
    }

    private var customSpeedInputBinding: Binding<String> {
        Binding(
            get: { customSpeedInput },
            set: { customSpeedInput = sanitizeNumericInput($0) }
        )
    }

    private var visibleMetricPreferences: [MetricPreference] {
        metricPreferences.filter(\.isVisible)
    }

    private var isCustomSpeedInputValid: Bool {
        guard let value = Double(customSpeedInput) else { return false }
        return value >= 0.1 && value <= 22.0
    }

    private func openEditCustomSpeed(slot: Int) {
        editingCustomSlot = slot
        let currentValue = slot == 1 ? customSpeedOne : customSpeedTwo
        customSpeedInput = String(format: "%.1f", currentValue)
        showCustomSpeedAlert = true
    }

    private func saveCustomSpeed() {
        guard isCustomSpeedInputValid else { return }
        _ = workoutViewModel.saveCustomSpeed(customSpeedInput, slot: editingCustomSlot)
    }

    private func sanitizeNumericInput(_ input: String) -> String {
        WorkoutInputSanitizer.numericText(input)
    }

    private func loadMetricPreferencesIfNeeded() {
        guard !didLoadMetricPreferences else { return }
        didLoadMetricPreferences = true
        metricPreferences = preferencesStore.loadMetricPreferences()
    }

    private func saveMetricPreferences() {
        preferencesStore.saveMetricPreferences(metricPreferences)
    }

    private func moveMetric(from source: IndexSet, to destination: Int) {
        metricPreferences.move(fromOffsets: source, toOffset: destination)
    }

    private func presentStatusToast(_ message: String) {
        toastWindowManager.show(
            message: message,
            showsProgress: message == "Looking for treadmills"
        )
    }
}

@MainActor
private final class StatusToastWindowManager: ObservableObject {
    private var window: UIWindow?
    private var dismissalWorkItem: DispatchWorkItem?
    private var isShowing = false
    private var toastID = UUID()

    func show(message: String, showsProgress: Bool) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }

        let toastWindow: UIWindow
        let shouldAnimateIn = !isShowing
        if let existingWindow = window, existingWindow.windowScene === scene {
            toastWindow = existingWindow
        } else {
            toastWindow = UIWindow(windowScene: scene)
            toastWindow.windowLevel = .alert
            toastWindow.backgroundColor = .clear
            toastWindow.isOpaque = false
            window = toastWindow
        }

        let controller = UIHostingController(
            rootView: GlobalStatusToastView(message: message, showsProgress: showsProgress)
        )
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        toastWindow.rootViewController = controller
        toastWindow.isUserInteractionEnabled = false
        toastWindow.isHidden = false

        toastID = UUID()
        isShowing = true
        toastWindow.layer.removeAllAnimations()
        if shouldAnimateIn {
            toastWindow.alpha = 0
            toastWindow.transform = CGAffineTransform(translationX: 0, y: -28)
            UIView.animate(
                withDuration: 0.38,
                delay: 0,
                usingSpringWithDamping: 0.84,
                initialSpringVelocity: 0.25,
                options: [.beginFromCurrentState, .allowUserInteraction]
            ) {
                toastWindow.alpha = 1
                toastWindow.transform = .identity
            }
        } else {
            toastWindow.alpha = 1
            toastWindow.transform = .identity
        }

        dismissalWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.hide()
        }
        dismissalWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: workItem)
    }

    private func hide() {
        guard isShowing, let window else { return }
        isShowing = false
        let hidingToastID = toastID

        UIView.animate(
            withDuration: 0.24,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseIn]
        ) {
            window.alpha = 0
            window.transform = CGAffineTransform(translationX: 0, y: -28)
        } completion: { [weak self, weak window] _ in
            guard let self, self.toastID == hidingToastID else { return }
            window?.isHidden = true
            window?.alpha = 1
            window?.transform = .identity
        }
    }
}

private struct GlobalStatusToastView: View {
    let message: String
    let showsProgress: Bool

    var body: some View {
        VStack {
            HStack(alignment: .center, spacing: 8) {
                if showsProgress {
                    ProgressView()
                        .controlSize(.small)
                        .tint(WorkoutTheme.controlAccent)
                        .frame(width: 22, height: 22)
                        .background(WorkoutTheme.controlAccent.opacity(0.12))
                        .clipShape(Circle())
                } else {
                    Image(systemName: message == "No treadmills found."
                          ? "exclamationmark.triangle.fill"
                          : "checkmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WorkoutTheme.controlAccent)
                        .frame(width: 22, height: 22)
                        .background(WorkoutTheme.controlAccent.opacity(0.12))
                        .clipShape(Circle())
                }

                Text(message)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: 300)
            .background(WorkoutTheme.panel)
            .clipShape(Capsule())
            .panelNoise(cornerRadius: 20)
            .overlay(Capsule().stroke(WorkoutTheme.paper.opacity(0.12)))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}
