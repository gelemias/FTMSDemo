//
//  ContentView.swift
//  FTMSDemo
//
//  Created by DELGADO Guillermo on 15/11/25.
//

import SwiftUI
import UIKit

enum WorkoutTheme {
    static let ink = adaptive(light: (0.851, 0.839, 0.816), dark: (0.200, 0.200, 0.200)) // #D9D6D0 / #333333
    static let panel = adaptive(light: (0.925, 0.918, 0.89), dark: (0.149, 0.149, 0.149))
    static let panelRaised = adaptive(light: (0.616, 0.651, 0.596), dark: (0.340, 0.360, 0.330)) // #9DA698 / #575C54
    static let paper = adaptive(light: (0.149, 0.149, 0.149), dark: (0.851, 0.839, 0.816)) // #262626 / #D9D6D0
    static let muted = adaptive(light: (0.380, 0.400, 0.365), dark: (0.616, 0.651, 0.596)) // #61665D / #9DA698
    static let orange = Color(red: 1.0, green: 0.8, blue: 0.0) // #FCCD00
    static let controlAccent = adaptive(light: (0.200, 0.200, 0.200), dark: (1.0, 0.8, 0.0)) // #333333 / #FCCD00
    static let primaryButtonForeground = adaptive(light: (0.149, 0.149, 0.149), dark: (0.200, 0.200, 0.200)) // #262626 / #333333

    private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(uiColor: UIColor { traits in
            let values = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: values.0, green: values.1, blue: values.2, alpha: 1)
        })
    }
}

private struct RubberFloorTexture: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let markColor = colorScheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.06)
            let highlightColor = colorScheme == .dark ? Color.black.opacity(0.12) : Color.white.opacity(0.26)

            for row in stride(from: 0.0, through: size.height + 16, by: 14) {
                for column in stride(from: 0.0, through: size.width + 16, by: 14) {
                    let offset = Int(row / 14).isMultiple(of: 2) ? 7.0 : 0.0
                    let x = column + offset
                    let y = row
                    let dot = CGRect(x: x, y: y, width: 2.2, height: 2.2)
                    context.fill(Path(ellipseIn: dot), with: .color(markColor))

                    if Int((x + y) / 14).isMultiple(of: 5) {
                        var seam = Path()
                        seam.move(to: CGPoint(x: x + 4, y: y + 7))
                        seam.addLine(to: CGPoint(x: x + 10, y: y + 10))
                        context.stroke(seam, with: .color(highlightColor), lineWidth: 0.7)
                    }
                }
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }
}

private struct NoiseTexture: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let lightGrain = colorScheme == .dark ? Color.white : Color.black
            let darkGrain = colorScheme == .dark ? Color.black : Color.white

            for row in stride(from: 0.0, through: size.height + 8, by: 8) {
                for column in stride(from: 0.0, through: size.width + 8, by: 8) {
                    let cellX = Int(column / 8)
                    let cellY = Int(row / 8)
                    var hash = UInt32(truncatingIfNeeded: cellX &* 374_761_393 &+ cellY &* 668_265_263)
                    hash ^= hash >> 13
                    hash &*= 1_274_126_177
                    hash ^= hash >> 16

                    let density = Double(hash % 1_000) / 1_000
                    guard density > 0.30 else { continue }

                    let jitterX = Double((hash >> 8) % 7)
                    let jitterY = Double((hash >> 16) % 7)
                    let size = density > 0.84 ? 1.45 : 1.0
                    let dotColor = density > 0.68 ? lightGrain : darkGrain
                    let opacity = density > 0.84 ? 0.070 : 0.035
                    let dot = CGRect(x: column + jitterX, y: row + jitterY, width: size, height: size)
                    context.fill(Path(ellipseIn: dot), with: .color(dotColor.opacity(opacity)))
                }
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }
}

extension View {
    func panelNoise(cornerRadius: CGFloat, enabled: Bool = true) -> some View {
        overlay {
            if enabled {
                NoiseTexture()
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
        }
    }
}

private struct TrainingPlanRowFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

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
    @State private var editingBlockID: UUID?
    @State private var draggedBlockID: UUID?
    @State private var trainingPlanRowFrames: [UUID: CGRect] = [:]
    @State private var swipedBlockID: UUID?
    @State private var didLoadTrainingPlan = false
    @State private var trainingPlanStartedAt: Date?
    @State private var showTrainingFlow = true
    @State private var trainingFlowDetent: PresentationDetent = .height(132)
    @State private var statusToastMessage: String?
    @State private var statusToastID = UUID()

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
                        .presentationDetents([.height(132), .large], selection: $trainingFlowDetent)
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
            }

            RubberFloorTexture()
                .opacity(0.7)
                .ignoresSafeArea()

            if let statusToastMessage {
                statusToast(message: statusToastMessage)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
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
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("BUILD THE WORK")
                            .font(.system(size: 30, weight: .black).italic())
                            .foregroundStyle(WorkoutTheme.orange)
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
                        .tint(WorkoutTheme.orange)
                        .foregroundStyle(WorkoutTheme.primaryButtonForeground)
                        .controlSize(.large)
                        .opacity(ftms.controlPointReady ? 1 : 0.55)
                    }
                }
                .padding()
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(TapGesture().onEnded { dismissKeyboard() })
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
            sendSpeed: { speed in ftms.sendTargetSpeed(kmh: speed) },
            startTreadmill: { ftms.startTreadmill() },
            stopTreadmill: { ftms.stopTreadmill() }
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
                        Menu {
                            Button("Save current plan", systemImage: "square.and.arrow.down") { saveNamedTrainingPlan() }
                            Button("Saved plans", systemImage: "folder") { showingSavedPlans = true }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title2)
                        }
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
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 10) {
                    ForEach($trainingPlanViewModel.blocks) { $block in
                        trainingPlanBlockRow(block: $block)
                    }
                    }
                }
                .coordinateSpace(name: "trainingPlanEditor")
                .onPreferenceChange(TrainingPlanRowFramePreferenceKey.self) { frames in
                    trainingPlanRowFrames = frames
                }
                .frame(height: min(max(editorListHeight, 86), maxEditorHeight))

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
                                    WorkoutTheme.controlAccent.opacity(0.75),
                                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                                )
                        }
                }
                .tint(WorkoutTheme.controlAccent)
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
                .overlay {
                    if draggedBlockID == blockID {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(WorkoutTheme.controlAccent, lineWidth: 2)
                            .padding(.horizontal, 14)
                    }
                }
                .scaleEffect(draggedBlockID == blockID ? 1.035 : 1)
                .zIndex(draggedBlockID == blockID ? 1 : 0)
                .animation(.snappy(duration: 0.18), value: draggedBlockID)
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
                case .second(true, let drag?):
                    guard draggedBlockID == blockID else { return }
                    reorderTrainingPlanBlock(at: drag.location.y)
                default:
                    break
                }
            }
            .onEnded { _ in
                guard draggedBlockID == blockID else { return }
                withAnimation(.snappy) {
                    draggedBlockID = nil
                }
            }
    }

    private func reorderTrainingPlanBlock(at y: CGFloat) {
        guard let draggedBlockID,
              let fromIndex = trainingPlanBlocks.firstIndex(where: { $0.id == draggedBlockID }) else { return }

        let destination: Int

        if let downwardTarget = trainingPlanBlocks.indices.reversed().first(where: { index in
            guard index > fromIndex,
                  let frame = trainingPlanRowFrames[trainingPlanBlocks[index].id] else { return false }
            return y > frame.midY
        }) {
            destination = downwardTarget + 1
        } else if let upwardTarget = trainingPlanBlocks.indices.first(where: { index in
            guard index < fromIndex,
                  let frame = trainingPlanRowFrames[trainingPlanBlocks[index].id] else { return false }
            return y < frame.midY
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
                    ContentUnavailableView("No saved plans", systemImage: "folder", description: Text("Save a plan from the menu to reuse it later."))
                } else {
                    ForEach(savedTrainingPlans) { plan in
                        Button {
                            trainingPlanViewModel.name = plan.name
                            trainingPlanViewModel.blocks = plan.blocks
                            showingSavedPlans = false
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(plan.name).font(.headline)
                                Text("\(plan.blocks.count) blocks · \(durationSummary(plan.blocks.reduce(0) { $0 + $1.totalDuration }))")
                                    .font(.caption).foregroundStyle(.secondary)
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
        trainingPlanViewModel.saveNamedPlan()
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
        let toastID = UUID()
        statusToastID = toastID

        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            statusToastMessage = message
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            guard statusToastID == toastID else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                statusToastMessage = nil
            }
        }
    }

    private func statusToast(message: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            if ftms.isScanning || ftms.isConnecting || ftms.isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(statusColor)
                    .controlSize(.small)
                    .frame(width: 22, height: 22)
                    .background(statusColor.opacity(0.12))
                    .clipShape(Circle())
            } else {
                Image(systemName: statusIconName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(statusColor)
                    .frame(width: 22, height: 22)
                    .background(statusColor.opacity(0.12))
                    .clipShape(Circle())
            }

            Text(message)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
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
    }

    private var statusIconName: String {
        if ftms.isConnecting {
            return "bolt.horizontal.circle.fill"
        }
        if ftms.isScanning {
            return "dot.radiowaves.left.and.right"
        }
        return "antenna.radiowaves.left.and.right"
    }

    private var statusColor: Color {
        if ftms.isConnecting {
            return WorkoutTheme.controlAccent
        }
        if ftms.isScanning {
            return WorkoutTheme.muted
        }
        return WorkoutTheme.muted
    }
}

struct DataRow: View {
    let label: String
    let value: Double?
    let unit: String

    init(label: String, value: Double?, unit: String) {
        self.label = label
        self.value = value
        self.unit = unit
    }

    init(label: String, value: Int?, unit: String) {
        self.label = label
        if let v = value {
            self.value = Double(v)
        } else {
            self.value = nil
        }
        self.unit = unit
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.callout)
            Spacer()
            if let value = value {
                Text(String(format: "%.1f %@", value, unit))
                    .font(.headline)
                    .bold()
            } else {
                Text("--")
            }
        }
    }
}
