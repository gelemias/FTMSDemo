import Foundation
import SwiftUI

/// Application-level coordinator. Feature-specific UI lives in `WorkoutView`,
/// `ConnectionView`, and `TrainingPlanFlowView`.
struct ContentView: View {
    @StateObject private var connection = ConnectionViewModel()
    @StateObject private var workout = WorkoutViewModel()
    @StateObject private var plan = TrainingPlanViewModel()
    @StateObject private var runner = TrainingPlanRunner()
    @StateObject private var toastManager = StatusToastWindowManager()
    @Environment(\.scenePhase) private var scenePhase
    private let preferencesStore = WorkoutPreferencesStore()
    @State private var metricPreferences = WorkoutPreferencesStore.defaultMetricPreferences
    @State private var didLoadMetricPreferences = false
    @State private var didLoadTrainingPlan = false
    @State private var showMetricCustomization = false
    @State private var showCustomSpeedAlert = false
    @State private var editingCustomSlot = 1
    @State private var customSpeedInput = ""
    @State private var trainingPlanStartedAt: Date?
    @State private var showTrainingFlow = true
    @State private var trainingFlowDetent: PresentationDetent = .height(80)

    var body: some View {
        ZStack(alignment: .top) {
            WorkoutTheme.ink.ignoresSafeArea()
            NavigationStack {
                Group {
                    if connection.isConnected {
                        connectedContent
                    } else {
                        ConnectionView(viewModel: connection)
                    }
                }
                    .background(Color.clear).navigationBarTitleDisplayMode(.inline).toolbar { connectionToolbar }
                    .sheet(isPresented: $showTrainingFlow) {
                        TrainingPlanFlowView(connection: connection, viewModel: plan, runner: runner,
                                             startedAt: $trainingPlanStartedAt, detent: $trainingFlowDetent,
                                             onStart: startTrainingPlan, onStop: stopTrainingPlan,
                                             onSetTargetSpeed: setTargetSpeed, onToast: presentStatusToast)
                            .presentationDetents([.height(80), .large], selection: $trainingFlowDetent)
                            .presentationDragIndicator(.visible)
                            .presentationBackground { ZStack { WorkoutTheme.panel; NoiseTexture() } }
                            .presentationBackgroundInteraction(.enabled(upThrough: .large))
                            .interactiveDismissDisabled(true)
                    }
                    .tint(WorkoutTheme.controlAccent)
                    .background { ZStack { WorkoutTheme.ink; RubberFloorTexture().opacity(0.7) }.ignoresSafeArea() }
            }
        }
        .onAppear {
            loadDataIfNeeded()
            presentStatusToast(connection.statusMessage)
        }
        .onChange(of: connection.statusMessage) { _, message in presentStatusToast(message) }
        .onChange(of: connection.isConnected) { _, connected in
            guard !connected else { return }
            runner.stop(); workout.isWorkoutRunning = false; trainingPlanStartedAt = nil
        }
    }

    @ViewBuilder private var connectedContent: some View {
        WorkoutView(connection: connection, isWorkoutRunning: $workout.isWorkoutRunning,
                    targetSpeedKmh: $workout.targetSpeedKmh, customSpeedOne: $workout.customSpeedOne,
                    customSpeedTwo: $workout.customSpeedTwo, metricPreferences: $metricPreferences,
                    onAdjustSpeed: adjustSpeed, onSetTargetSpeed: setTargetSpeed,
                    onEditCustomSpeed: openEditCustomSpeed, onShowMetrics: { showMetricCustomization = true },
                    onToggleWorkout: toggleWorkoutState)
            .onChange(of: connection.treadmillData.speedKmh) { _, speed in
                guard let speed, abs(speed - workout.targetSpeedKmh) > 0.2 else { return }
                workout.targetSpeedKmh = (speed * 10).rounded() / 10
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { runner.refresh() } }
            .onChange(of: metricPreferences) { _, _ in preferencesStore.saveMetricPreferences(metricPreferences) }
            .onChange(of: plan.blocks) { _, _ in plan.saveBlocks() }
            .alert("Edit custom speed", isPresented: $showCustomSpeedAlert) {
                TextField("km/h", text: customSpeedInputBinding).keyboardType(.decimalPad)
                Button("Cancel", role: .cancel) {}
                Button("Save", action: saveCustomSpeed).disabled(!isCustomSpeedInputValid)
            } message: { Text("Enter a number between 0.1 and 22.0 km/h.") }
            .sheet(isPresented: $showMetricCustomization) {
                MetricCustomizationView(preferences: $metricPreferences, onMove: moveMetric,
                                        onDone: { showMetricCustomization = false })
            }
    }

    @ToolbarContentBuilder private var connectionToolbar: some ToolbarContent {
        if connection.isConnected {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: toggleWorkoutState) {
                    Label(workout.isWorkoutRunning ? "Stop" : "Run", systemImage: workout.isWorkoutRunning ? "stop.fill" : "play.fill")
                }.tint(WorkoutTheme.controlAccent).disabled(!connection.controlPointReady)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { connection.disconnect(); workout.isWorkoutRunning = false } label: {
                    Label("Disconnect", systemImage: "bolt.slash")
                }.tint(WorkoutTheme.paper)
            }
        }
    }

    private func loadDataIfNeeded() {
        guard !didLoadTrainingPlan else { return }
        didLoadTrainingPlan = true; plan.loadIfNeeded()
        guard !didLoadMetricPreferences else { return }
        didLoadMetricPreferences = true; metricPreferences = preferencesStore.loadMetricPreferences()
    }
    private func setTargetSpeed(_ speed: Double) { connection.sendTargetSpeed(kmh: workout.setTargetSpeed(speed)) }
    private func adjustSpeed(by delta: Double) { connection.sendTargetSpeed(kmh: workout.adjustSpeed(by: delta)) }
    private func toggleWorkoutState() {
        if workout.isWorkoutRunning {
            if trainingPlanStartedAt != nil { stopTrainingPlan() } else { connection.stopTreadmill(); workout.isWorkoutRunning = false }
        } else { connection.startTreadmill(); workout.isWorkoutRunning = true }
    }
    private func startTrainingPlan() {
        guard connection.controlPointReady else { return }
        trainingPlanStartedAt = Date()
        runner.start(blocks: plan.blocks, workoutName: plan.name, treadmillName: connection.connectedDeviceName ?? "Treadmill",
                     actions: TrainingPlanRunnerActions(sendSpeed: { connection.sendTargetSpeed(kmh: $0) },
                                                        startTreadmill: connection.startTreadmill,
                                                        stopTreadmill: connection.stopTreadmill))
        workout.isWorkoutRunning = true
    }
    private func stopTrainingPlan() { runner.stop(); workout.isWorkoutRunning = false; trainingPlanStartedAt = nil }
    private var customSpeedInputBinding: Binding<String> {
        Binding(get: { customSpeedInput }, set: { customSpeedInput = WorkoutInputSanitizer.numericText($0) })
    }
    private var isCustomSpeedInputValid: Bool {
        guard let value = Double(customSpeedInput) else { return false }
        return (0.1...22.0).contains(value)
    }
    private func openEditCustomSpeed(slot: Int) {
        editingCustomSlot = slot
        customSpeedInput = String(format: "%.1f", slot == 1 ? workout.customSpeedOne : workout.customSpeedTwo)
        showCustomSpeedAlert = true
    }
    private func saveCustomSpeed() { _ = workout.saveCustomSpeed(customSpeedInput, slot: editingCustomSlot) }
    private func moveMetric(from source: IndexSet, to destination: Int) { metricPreferences.move(fromOffsets: source, toOffset: destination) }
    private func presentStatusToast(_ message: String) { toastManager.show(message: message, showsProgress: message == "Looking for treadmills") }
}
