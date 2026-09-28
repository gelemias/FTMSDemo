//
//  ContentView.swift
//  FTMSDemo
//
//  Created by DELGADO Guillermo on 15/11/25.
//

import SwiftUI
import UIKit

private enum MetricID: String, CaseIterable, Codable, Identifiable {
    case distance
    case pace
    case speed
    case incline
    case cadence
    case heartRate

    var id: String { rawValue }
}

private struct MetricPreference: Identifiable, Codable, Equatable {
    let id: MetricID
    var isVisible: Bool
}

private enum WorkoutTheme {
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

private extension View {
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
    @StateObject private var ftms = FTMSManager()
    @StateObject private var trainingPlanRunner = TrainingPlanRunner()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("metric_preferences_json") private var metricPreferencesStorage = ""
    @AppStorage("training_plan_blocks_json") private var trainingPlanStorage = ""
    @AppStorage("saved_training_plans_json") private var savedTrainingPlansStorage = ""
    @AppStorage("training_plan_steps_json") private var legacyTrainingPlanStorage = ""
    @State private var targetSpeedKmh = 10.0
    @State private var customSpeedOne = 8.0
    @State private var customSpeedTwo = 13.0
    @State private var isWorkoutRunning = false
    @State private var showCustomSpeedAlert = false
    @State private var editingCustomSlot = 1
    @State private var customSpeedInput = ""
    @State private var metricPreferences: [MetricPreference] = Self.defaultMetricPreferences()
    @State private var showMetricCustomization = false
    @State private var didLoadMetricPreferences = false
    @State private var trainingPlanBlocks = TrainingPlan.todayBlocks
    @State private var trainingPlanName = "Speed builder"
    @State private var savedTrainingPlans: [TrainingPlanTemplate] = []
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
                    isWorkoutRunning = false
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
                                isWorkoutRunning = false
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
        connectionPrelude
    }

    private var connectionPrelude: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("READY TO WORK?")
                        .font(.system(size: 34, weight: .black).italic())
                        .foregroundStyle(WorkoutTheme.orange)

                    Text("Connect your treadmill. Keep your eyes on the belt, not the screen.")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(WorkoutTheme.paper)
                }

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("NEARBY MACHINES")
                            .font(.caption.weight(.black))
                            .tracking(1.2)
                            .foregroundStyle(WorkoutTheme.muted)
                        Spacer()
                        if ftms.isScanning {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    if ftms.discoveredTreadmills.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 12) {
                            ForEach(ftms.discoveredTreadmills) { treadmill in
                                Button {
                                    ftms.connect(to: treadmill.id)
                                } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: "figure.run")
                                            .font(.title3)
                                            .foregroundStyle(WorkoutTheme.controlAccent)
                                            .frame(width: 36, height: 36)
                                            .background(WorkoutTheme.controlAccent.opacity(0.12))
                                            .clipShape(RoundedRectangle(cornerRadius: 10))

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(treadmill.name)
                                                .font(.headline)
                                                .foregroundStyle(.primary)
                                            Text("Signal \(treadmill.rssi) dBm")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        if ftms.selectedTreadmillID == treadmill.id && ftms.isConnecting {
                                            ProgressView()
                                        } else {
                                            Image(systemName: "chevron.right")
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .padding()
                                    .background(WorkoutTheme.panel)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .panelNoise(cornerRadius: 14)
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(WorkoutTheme.paper.opacity(0.08)))
                                }
                                .buttonStyle(.plain)
                                .disabled(ftms.isConnecting)
                            }
                        }
                    }
                }

                Button {
                    guard !ftms.isScanning && !ftms.isConnecting else { return }
                    ftms.startScan()
                } label: {
                    Label(ftms.isScanning ? "Scanning..." : "Search Again", systemImage: "arrow.clockwise")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(WorkoutTheme.orange)
                .foregroundStyle(WorkoutTheme.primaryButtonForeground)
                .controlSize(.large)
                .opacity(ftms.isScanning || ftms.isConnecting ? 0.55 : 1)
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
        .safeAreaPadding(.bottom, 144)
        .navigationTitle("FTMS")
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
        ScrollView {
            VStack(spacing: 14) {
                workoutStatusStrip
                primaryMetricCard
                VStack(spacing: 16) {
                    HStack {
                        Text("SET PACE")
                            .font(.caption.weight(.black))
                            .tracking(1.2)
                            .foregroundStyle(WorkoutTheme.muted)
                        Spacer()
                        Button {
                            showMetricCustomization = true
                        } label: {
                            Label("Metrics", systemImage: "slider.horizontal.3")
                                .font(.caption.weight(.bold))
                        }
                        .tint(WorkoutTheme.muted)
                    }

                    HStack(spacing: 16) {
                        Button {
                            adjustSpeed(by: -0.1)
                        } label: {
                            Image(systemName: "minus")
                                .font(.title.weight(.black))
                                .frame(width: 76, height: 76)
                                .background(WorkoutTheme.panelRaised)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .panelNoise(cornerRadius: 14)
                        }
                        .buttonStyle(.plain)
                        .disabled(!ftms.controlPointReady)

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

                        Button {
                            adjustSpeed(by: 0.1)
                        } label: {
                            Image(systemName: "plus")
                                .font(.title.weight(.black))
                                .frame(width: 76, height: 76)
                                .background(WorkoutTheme.panelRaised)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .panelNoise(cornerRadius: 14)
                        }
                        .buttonStyle(.plain)
                        .disabled(!ftms.controlPointReady)
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach([10.0, 12.0, 14.0, 16.0], id: \.self) { quickSpeed in
                            Button {
                                setTargetSpeed(quickSpeed)
                            } label: {
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
                            .disabled(!ftms.controlPointReady)
                        }
                        customShortcutTile(speed: customSpeedOne, slot: 1)
                        customShortcutTile(speed: customSpeedTwo, slot: 2)
                    }
                }
                .padding()
                .background(WorkoutTheme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .panelNoise(cornerRadius: 16)

                Button {
                    toggleWorkoutState()
                } label: {
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
                .disabled(!ftms.controlPointReady)

            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .scrollContentBackground(.hidden)
        .safeAreaPadding(.bottom, 144)
        .navigationTitle("CONTROL")
        .onChange(of: ftms.treadmillData.speedKmh) { _, newValue in
            guard let newValue else { return }
            if abs(newValue - targetSpeedKmh) > 0.2 {
                targetSpeedKmh = (newValue * 10).rounded() / 10
            }
        }
        .onChange(of: ftms.isConnected) { _, isConnected in
            if !isConnected {
                isWorkoutRunning = false
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
            metricCustomizationSheet
        }
    }

    private var workoutStatusStrip: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(WorkoutTheme.controlAccent)
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(isWorkoutRunning ? "WORKOUT LIVE" : "MACHINE READY")
                    .font(.caption.weight(.black))
                    .tracking(1.1)
                Text(ftms.connectedDeviceName ?? "Treadmill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(WorkoutTheme.muted)
            }
            Spacer()
            if ftms.isLoading { ProgressView().tint(WorkoutTheme.controlAccent) }
        }
        .padding(.horizontal, 4)
    }

    private var primaryMetricCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CURRENT SPEED")
                        .font(.caption.weight(.black))
                        .tracking(1.2)
                        .foregroundStyle(WorkoutTheme.muted)
                    Text(String(format: "%.1f", ftms.treadmillData.speedKmh ?? 0))
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
                    Text(String(format: "%.1f", ftms.treadmillData.distanceKilometers))
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
                compactMetric(label: "PACE", value: ftms.treadmillData.paceMinPerKm.map { String(format: "%.1f", $0) } ?? "--", unit: "MIN/KM")
                compactMetric(label: "INCLINE", value: ftms.treadmillData.incline.map { String(format: "%.1f", $0) } ?? "--", unit: "%")
                compactMetric(label: "HEART", value: ftms.treadmillData.heartRate.map { String($0) } ?? "--", unit: "BPM")
            }

            let additionalMetrics = visibleMetricPreferences.filter { ![.speed, .distance, .pace, .incline, .heartRate].contains($0.id) }
            if !additionalMetrics.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(additionalMetrics) { preference in
                        metricChip(for: preference.id)
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

    @ViewBuilder
    private func metricChip(for metricID: MetricID) -> some View {
        switch metricID {
        case .cadence:
            compactMetric(label: "CADENCE", value: ftms.treadmillData.cadenceSpm.map { String($0) } ?? "--", unit: "SPM")
        case .distance, .pace, .speed, .incline, .heartRate:
            EmptyView()
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
        let normalized = max(0.0, min(22.0, (speed * 10).rounded() / 10))
        targetSpeedKmh = normalized
        ftms.sendTargetSpeed(kmh: normalized)
    }

    private func adjustSpeed(by delta: Double) {
        setTargetSpeed(targetSpeedKmh + delta)
    }

    private func toggleWorkoutState() {
        if isWorkoutRunning {
            if trainingPlanStartedAt != nil {
                stopTrainingPlan()
            } else {
                ftms.stopTreadmill()
                isWorkoutRunning = false
            }
        } else {
            ftms.startTreadmill()
            isWorkoutRunning = true
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
        isWorkoutRunning = true
    }

    private func stopTrainingPlan() {
        trainingPlanRunner.stop()
        isWorkoutRunning = false
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
                            TextField("Workout name", text: $trainingPlanName)
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
                    ForEach($trainingPlanBlocks) { $block in
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
                    trainingPlanEditSheet(block: $trainingPlanBlocks[index])
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
                    trainingPlanBlocks.removeAll { $0.id == blockID }
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
            trainingPlanBlocks.move(
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
        trainingPlanBlocks.insert(block, at: max(0, trainingPlanBlocks.count - 1))
    }

    private func moveTrainingPlanBlocks(from source: IndexSet, to destination: Int) {
        trainingPlanBlocks.move(fromOffsets: source, toOffset: destination)
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
                            trainingPlanName = plan.name
                            trainingPlanBlocks = plan.blocks
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
        trainingPlanName = name
        savedTrainingPlans.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        savedTrainingPlans.insert(TrainingPlanTemplate(name: name, blocks: trainingPlanBlocks), at: 0)
        persistSavedTrainingPlans()
    }

    private func deleteSavedPlan(_ plan: TrainingPlanTemplate) {
        savedTrainingPlans.removeAll { $0.id == plan.id }
        persistSavedTrainingPlans()
    }

    private func persistSavedTrainingPlans() {
        guard let data = try? JSONEncoder().encode(savedTrainingPlans), let json = String(data: data, encoding: .utf8) else { return }
        savedTrainingPlansStorage = json
    }

    private func currentTrainingStep(for elapsed: TimeInterval) -> TrainingPlanStep? {
        guard trainingPlanStartedAt != nil else { return trainingPlanSteps.first }
        var consumed: TimeInterval = 0
        for step in trainingPlanSteps {
            consumed += step.durationSeconds
            if elapsed < consumed { return step }
        }
        return nil
    }

    private var trainingPlanSteps: [TrainingPlanStep] {
        trainingPlanBlocks.flatMap { $0.expandedSteps() }
    }

    private var trainingPlanDuration: TimeInterval {
        trainingPlanBlocks.reduce(0) { $0 + $1.totalDuration }
    }

    private var intervalCount: Int {
        trainingPlanBlocks.filter { $0.kind == .intervalGroup }.reduce(0) { $0 + max(1, $1.repetitions) }
    }

    private func durationSummary(_ seconds: TimeInterval) -> String {
        let wholeMinutes = Int(seconds) / 60
        let remainder = Int(seconds) % 60
        if remainder == 0 { return "\(wholeMinutes) min total" }
        return String(format: "%d:%02d total", wholeMinutes, remainder)
    }

    private func timeIntoCurrentStep(_ elapsed: TimeInterval) -> TimeInterval {
        var consumed: TimeInterval = 0
        for step in trainingPlanSteps {
            if elapsed < consumed + step.durationSeconds { return elapsed - consumed }
            consumed += step.durationSeconds
        }
        return 0
    }

    private func timeLabel(for seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func speedLabel(_ speed: Double) -> String {
        String(format: "%.1f km/h", speed)
    }

    private func loadTrainingPlanIfNeeded() {
        guard !didLoadTrainingPlan else { return }
        didLoadTrainingPlan = true

        if let data = savedTrainingPlansStorage.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([TrainingPlanTemplate].self, from: data) {
            savedTrainingPlans = decoded
        }

        guard let data = trainingPlanStorage.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([TrainingPlanBlock].self, from: data),
              !decoded.isEmpty else {
            if let legacyData = legacyTrainingPlanStorage.data(using: .utf8),
               let legacySteps = try? JSONDecoder().decode([TrainingPlanStep].self, from: legacyData),
               !legacySteps.isEmpty {
                trainingPlanBlocks = legacySteps.enumerated().map { index, step in
                    TrainingPlanBlock(
                        kind: index == 0 ? .warmUp : (index == legacySteps.count - 1 ? .coolDown : .intervalGroup),
                        durationSeconds: step.durationSeconds,
                        targetSpeedKmh: step.targetSpeedKmh,
                        repetitions: 1,
                        recoveryDurationSeconds: 0,
                        recoverySpeedKmh: step.targetSpeedKmh
                    )
                }
                saveTrainingPlan()
                return
            }
            trainingPlanBlocks = TrainingPlan.todayBlocks
            return
        }

        trainingPlanBlocks = decoded
    }

    private func saveTrainingPlan() {
        guard let data = try? JSONEncoder().encode(trainingPlanBlocks),
              let json = String(data: data, encoding: .utf8) else { return }
        trainingPlanStorage = json
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

    private func customShortcutTile(speed: Double, slot: Int) -> some View {
        HStack(spacing: 8) {
            Button {
                setTargetSpeed(speed)
            } label: {
                Text(String(format: "%.1f km/h", speed))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 72)
                    .foregroundStyle(targetSpeedKmh == speed ? WorkoutTheme.ink : WorkoutTheme.paper)
            }
            .buttonStyle(.plain)
            .disabled(!ftms.controlPointReady)

            Button {
                openEditCustomSpeed(slot: slot)
            } label: {
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

    private func openEditCustomSpeed(slot: Int) {
        editingCustomSlot = slot
        let currentValue = slot == 1 ? customSpeedOne : customSpeedTwo
        customSpeedInput = String(format: "%.1f", currentValue)
        showCustomSpeedAlert = true
    }

    private func saveCustomSpeed() {
        guard let newValue = Double(customSpeedInput), isCustomSpeedInputValid else { return }
        let normalized = max(0.1, min(22.0, (newValue * 10).rounded() / 10))
        if editingCustomSlot == 1 {
            customSpeedOne = normalized
        } else {
            customSpeedTwo = normalized
        }
    }

    private func sanitizeNumericInput(_ input: String) -> String {
        let normalized = input.replacingOccurrences(of: ",", with: ".")
        var result = ""
        var hasDecimalSeparator = false
        for character in normalized {
            if character.isNumber {
                result.append(character)
            } else if character == ".", !hasDecimalSeparator {
                hasDecimalSeparator = true
                result.append(character)
            }
        }
        return result
    }
    
    @ViewBuilder
    private func metricRow(for metricID: MetricID) -> some View {
        switch metricID {
        case .distance:
            DataRow(label: "Distance", value: ftms.treadmillData.distanceKilometers, unit: "km")
        case .pace:
            DataRow(label: "Pace", value: ftms.treadmillData.paceMinPerKm, unit: "min/km")
        case .speed:
            DataRow(label: "Speed", value: ftms.treadmillData.speedKmh, unit: "km/h")
        case .incline:
            DataRow(label: "Incline", value: ftms.treadmillData.incline, unit: "%")
        case .cadence:
            DataRow(label: "Cadence (est.)", value: ftms.treadmillData.cadenceSpm, unit: "spm")
        case .heartRate:
            DataRow(label: "Heart Rate", value: ftms.treadmillData.heartRate, unit: "bpm")
        }
    }
    
    private var metricCustomizationSheet: some View {
        NavigationStack {
            List {
                ForEach($metricPreferences) { $preference in
                    HStack {
                        Text(metricTitle(preference.id))
                        Spacer()
                        Toggle("Visible", isOn: $preference.isVisible)
                            .labelsHidden()
                    }
                }
                .onMove(perform: moveMetric)
            }
            .navigationTitle("Customize Metrics")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showMetricCustomization = false
                    }
                }
            }
        }
    }
    
    private func metricTitle(_ id: MetricID) -> String {
        switch id {
        case .distance: return "Distance"
        case .pace: return "Pace"
        case .speed: return "Speed"
        case .incline: return "Incline"
        case .cadence: return "Cadence"
        case .heartRate: return "Heart Rate"
        }
    }

    private static func defaultMetricPreferences() -> [MetricPreference] {
        MetricID.allCases.map { MetricPreference(id: $0, isVisible: true) }
    }
    
    private func loadMetricPreferencesIfNeeded() {
        guard !didLoadMetricPreferences else { return }
        didLoadMetricPreferences = true

        guard let data = metricPreferencesStorage.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([MetricPreference].self, from: data) else {
            metricPreferences = Self.defaultMetricPreferences()
            return
        }
        
        metricPreferences = normalizedMetricPreferences(decoded)
    }
    
    private func normalizedMetricPreferences(_ preferences: [MetricPreference]) -> [MetricPreference] {
        var seen = Set<MetricID>()
        var normalized: [MetricPreference] = []
        
        for preference in preferences where !seen.contains(preference.id) {
            normalized.append(preference)
            seen.insert(preference.id)
        }
        
        for metric in MetricID.allCases where !seen.contains(metric) {
            normalized.append(MetricPreference(id: metric, isVisible: true))
        }
        
        return normalized
    }
    
    private func saveMetricPreferences() {
        guard let data = try? JSONEncoder().encode(metricPreferences),
              let json = String(data: data, encoding: .utf8) else { return }
        metricPreferencesStorage = json
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

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No treadmills found yet")
                .font(.headline)
            Text("Make sure the treadmill is powered on and advertising over Bluetooth, then keep this screen open for a few seconds.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(WorkoutTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .panelNoise(cornerRadius: 18)
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
