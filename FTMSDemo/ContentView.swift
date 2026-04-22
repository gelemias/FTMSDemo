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

struct ContentView: View {

    @StateObject private var ftms = FTMSManager()
    @AppStorage("metric_preferences_json") private var metricPreferencesStorage = ""
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

    var body: some View {
        NavigationStack {
            Group {
                if ftms.isConnected {
                    connectedDashboard
                } else {
                    connectionPrelude
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if ftms.isConnected {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            toggleWorkoutState()
                        } label: {
                            Image(systemName: isWorkoutRunning ? "stop.fill" : "play.fill")
                        }
                        .disabled(!ftms.controlPointReady)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            ftms.disconnect()
                            isWorkoutRunning = false
                        } label: {
                            Image(systemName: "bolt.slash")
                        }
                    }
                }
            }
        }
    }

    private var connectionPrelude: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Connect to treadmill")
                        .font(.largeTitle.bold())

                    Text("Nearby FTMS treadmills will appear below. Pick your machine to connect and the control panel will open as soon as the connection is ready.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                statusCard

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Nearby Devices")
                            .font(.title3.bold())
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
                                            .foregroundStyle(.blue)
                                            .frame(width: 36, height: 36)
                                            .background(Color.blue.opacity(0.12))
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
                                    .background(Color(uiColor: .secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 18))
                                }
                                .buttonStyle(.plain)
                                .disabled(ftms.isConnecting)
                            }
                        }
                    }
                }

                Button {
                    ftms.startScan()
                } label: {
                    Label(ftms.isScanning ? "Scanning..." : "Search Again", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(ftms.isScanning || ftms.isConnecting)
            }
            .padding()
        }
        .navigationTitle("FTMS Demo")
    }

    private var connectedDashboard: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Connected to \(ftms.connectedDeviceName ?? "treadmill")", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)

                    HStack {
                        if ftms.isLoading {
                            ProgressView()
                        }
                        Text(ftms.statusMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.green.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 18))

                Divider()

                VStack(spacing: 10) {
                    HStack {
                        Text("Metrics")
                            .font(.headline)
                        
                        Spacer()
                        
                        Button {
                            showMetricCustomization = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                    }
                    
                    if visibleMetricPreferences.isEmpty {
                        Text("No metrics selected. Tap Customize to choose what to display.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(visibleMetricPreferences) { preference in
                            metricRow(for: preference.id)
                        }
                    }
                }
                .padding()

                Divider()

                VStack(spacing: 16) {
                    Text("Target Speed")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 16) {
                        Button {
                            adjustSpeed(by: -0.1)
                        } label: {
                            Image(systemName: "minus")
                                .font(.title2.weight(.semibold))
                                .frame(width: 52, height: 52)
                                .background(Color(uiColor: .systemGray5))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!ftms.controlPointReady)

                        VStack(spacing: 2) {
                            Text(String(format: "%.1f km/h", targetSpeedKmh))
                                .font(.title2.weight(.bold))
                            Text(String(format: "%.1f min/km", paceForSpeed(targetSpeedKmh)))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)

                        Button {
                            adjustSpeed(by: 0.1)
                        } label: {
                            Image(systemName: "plus")
                                .font(.title2.weight(.semibold))
                                .frame(width: 52, height: 52)
                                .background(Color(uiColor: .systemGray5))
                                .clipShape(Circle())
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
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(targetSpeedKmh == quickSpeed ? Color.blue : Color(uiColor: .systemGray5))
                                    .foregroundStyle(targetSpeedKmh == quickSpeed ? .white : .primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .disabled(!ftms.controlPointReady)
                        }
                        customShortcutTile(speed: customSpeedOne, slot: 1)
                        customShortcutTile(speed: customSpeedTwo, slot: 2)
                    }
                }
                .padding()
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))

            }
            .padding()
        }
        .navigationTitle("Treadmill")
        .onChange(of: ftms.treadmillData.speedKmh) { _, newValue in
            guard let newValue else { return }
            if abs(newValue - targetSpeedKmh) > 0.2 {
                targetSpeedKmh = (newValue * 10).rounded() / 10
            }
        }
        .onChange(of: ftms.isConnected) { _, isConnected in
            if !isConnected {
                isWorkoutRunning = false
            }
        }
        .onChange(of: metricPreferences) { _, _ in
            saveMetricPreferences()
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
            ftms.stopTreadmill()
            isWorkoutRunning = false
        } else {
            ftms.startTreadmill()
            isWorkoutRunning = true
        }
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
                    .padding(.vertical, 12)
                    .foregroundStyle(targetSpeedKmh == speed ? .white : .primary)
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
        .background(targetSpeedKmh == speed ? Color.blue : Color(uiColor: .systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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

    private var statusCard: some View {
        HStack(alignment: .center, spacing: 12) {
            if ftms.isScanning || ftms.isConnecting || ftms.isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(statusColor)
                    .frame(width: 36, height: 36)
                    .background(statusColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Image(systemName: statusIconName)
                    .font(.title3)
                    .foregroundStyle(statusColor)
                    .frame(width: 36, height: 36)
                    .background(statusColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(ftms.statusMessage)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                if ftms.isConnecting {
                    Text("Stay close to the treadmill while the Bluetooth connection completes.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            Spacer()
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
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
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
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
            return .orange
        }
        if ftms.isScanning {
            return .blue
        }
        return .secondary
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
