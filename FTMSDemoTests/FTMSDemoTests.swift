//
//  FTMSDemoTests.swift
//  FTMSDemoTests
//
//  Created by DELGADO Guillermo on 22/4/26.
//

import CoreBluetooth
@testable import FTMSDemo
import Testing

struct FTMSDemoTests {
    @Test func parsesTreadmillDataAndDerivesMetrics() {
        // Flags: total distance, incline, instant pace, and heart rate.
        let packet = Data([
            0x2C, 0x01,       // flags
            0xD2, 0x04,       // 12.34 km/h
            0x40, 0xE2, 0x01, // 123,456 m
            0x32, 0x00,       // +5.0% incline
            0x00, 0x00,       // ramp angle
            0x2D, 0x00,       // 4.5 min/km
            0x78,              // 120 bpm
        ])

        let result = FTMSDataParser().parse(packet)

        #expect(result?.speedKmh == 12.34)
        #expect(result?.distanceMeters == 123_456)
        #expect(result?.incline == 5.0)
        #expect(result?.paceMinPerKm == 4.5)
        #expect(result?.heartRate == 120)
        #expect(result?.cadenceSpm == 222)
    }

    @Test func parserRejectsPacketsMissingRequiredFields() {
        #expect(FTMSDataParser().parse(Data([0x00])) == nil)
        #expect(FTMSDataParser().parse(Data([0x00, 0x00, 0x01])) == nil)
    }

    @Test func commandEncoderBuildsLittleEndianControlPointPackets() {
        #expect(FTMSCommandEncoder.controlPoint(opcode: 0x07) == Data([0x07]))
        #expect(FTMSCommandEncoder.targetSpeed(kmh: 12.34) == Data([0x02, 0xD2, 0x04]))
    }

    @Test func trainingPlanCalculatorUsesExpandedStepsAndBoundaries() {
        let blocks = [
            TrainingPlanBlock(kind: .warmUp, durationSeconds: 60, targetSpeedKmh: 8),
            TrainingPlanBlock(kind: .intervalGroup, durationSeconds: 30, targetSpeedKmh: 12, repetitions: 2, recoveryDurationSeconds: 15, recoverySpeedKmh: 8),
            TrainingPlanBlock(kind: .coolDown, durationSeconds: 45, targetSpeedKmh: 6),
        ]

        let steps = TrainingPlanCalculator.steps(from: blocks)

        #expect(steps.count == 4)
        #expect(TrainingPlanCalculator.duration(of: blocks) == 150)
        #expect(TrainingPlanCalculator.intervalCount(in: blocks) == 2)
        #expect(TrainingPlanCalculator.currentStep(in: blocks, elapsed: 60, isRunning: true)?.phase == .interval)
        #expect(TrainingPlanCalculator.elapsedInCurrentStep(in: blocks, elapsed: 75) == 15)
        #expect(TrainingPlanCalculator.currentStep(in: blocks, elapsed: 150, isRunning: true) == nil)
    }

    @Test func trainingPlanStorePreservesPlansAndMigratesLegacySteps() {
        let defaults = UserDefaults(suiteName: "FTMSDemoTests.\(UUID().uuidString)")!
        let store = TrainingPlanStore(defaults: defaults)
        let legacySteps = [
            TrainingPlanStep(title: "Warm up", durationSeconds: 60, targetSpeedKmh: 8, phase: .warmUp),
            TrainingPlanStep(title: "Run", durationSeconds: 120, targetSpeedKmh: 10, phase: .steadyRun),
            TrainingPlanStep(title: "Cool down", durationSeconds: 60, targetSpeedKmh: 6, phase: .coolDown),
        ]
        let legacyData = try? JSONEncoder().encode(legacySteps)
        defaults.set(String(data: legacyData ?? Data(), encoding: .utf8), forKey: "training_plan_steps_json")

        let migrated = store.loadBlocks()
        #expect(migrated.count == 3)
        #expect(migrated.first?.kind == .warmUp)
        #expect(migrated.last?.kind == .coolDown)
        #expect(store.loadBlocks() == migrated)

        let template = TrainingPlanTemplate(name: "Intervals", blocks: migrated)
        store.saveSavedPlans([template])
        #expect(store.loadSavedPlans() == [template])
    }

    @Test func workoutPreferencesNormalizeMetricsAndPersistCustomSpeeds() {
        let defaults = UserDefaults(suiteName: "FTMSDemoTests.\(UUID().uuidString)")!
        let store = WorkoutPreferencesStore(defaults: defaults)

        store.saveMetricPreferences([
            MetricPreference(id: .speed, isVisible: false),
            MetricPreference(id: .speed, isVisible: true),
        ])
        let metrics = store.loadMetricPreferences()
        #expect(metrics.count == MetricID.allCases.count)
        #expect(metrics.first?.id == .speed)
        #expect(metrics.first?.isVisible == false)

        store.saveCustomSpeed(9.5, slot: 1)
        store.saveCustomSpeed(14.5, slot: 2)
        let speeds = store.loadCustomSpeeds()
        #expect(speeds.first == 9.5)
        #expect(speeds.second == 14.5)
        #expect(WorkoutInputSanitizer.numericText("12,3 km/h") == "12.3")
    }

    @Test func todayTrainingPlanMatchesWorkoutStructure() {
        let plan = TrainingPlan.today

        #expect(plan.steps.count == 10)
        #expect(plan.steps.filter { $0.phase == .interval }.count == 4)
        #expect(plan.steps.filter { $0.phase == .recovery }.count == 4)
        #expect(plan.steps.first?.durationSeconds == 12 * 60)
        #expect(plan.steps.last?.durationSeconds == 10 * 60)
        #expect(plan.totalDuration == 48 * 60)
        #expect(plan.steps[1].targetSpeedKmh == 13.0)
        #expect(plan.steps[2].durationSeconds == 150)
    }

    @Test func scanningResetsPreviousSelectionAndSetsPreludeStatus() {
        var presentation = FTMSConnectionPresentation(
            statusMessage: "Connected to DeckRun.",
            isLoading: false,
            isScanning: false,
            isConnecting: false,
            isConnected: true,
            connectedDeviceName: "DeckRun",
            discoveredTreadmills: [
                DiscoveredTreadmill(id: UUID(), name: "Old Treadmill", rssi: -70)
            ],
            selectedTreadmillID: UUID()
        )

        presentation.beginScanning()

        #expect(presentation.isLoading)
        #expect(presentation.isScanning)
        #expect(!presentation.isConnecting)
        #expect(!presentation.isConnected)
        #expect(presentation.connectedDeviceName == nil)
        #expect(presentation.discoveredTreadmills.isEmpty)
        #expect(presentation.selectedTreadmillID == nil)
        #expect(presentation.statusMessage == "Looking for treadmills")
    }

    @Test func discoveredTreadmillsAreUpsertedAndSortedBySignalStrength() {
        let weakerID = UUID()
        let strongerID = UUID()
        var presentation = FTMSConnectionPresentation()

        presentation.addOrUpdateDiscoveredTreadmill(id: weakerID, name: "Living Room Run", rssi: -75)
        presentation.addOrUpdateDiscoveredTreadmill(id: strongerID, name: "Gym Beast", rssi: -50)
        presentation.addOrUpdateDiscoveredTreadmill(id: weakerID, name: "Living Room Run", rssi: -42)

        #expect(presentation.discoveredTreadmills.count == 2)
        #expect(presentation.discoveredTreadmills.map(\.id) == [weakerID, strongerID])
        #expect(presentation.discoveredTreadmills.first?.rssi == -42)
        #expect(presentation.statusMessage == "2 treadmills found nearby.")
    }

    @Test func connectionFlowPublishesClearUserFacingStatus() {
        let selectedID = UUID()
        var presentation = FTMSConnectionPresentation()

        presentation.beginConnecting(to: selectedID, name: "NordicTrack")
        #expect(presentation.selectedTreadmillID == selectedID)
        #expect(presentation.isConnecting)
        #expect(!presentation.isScanning)
        #expect(presentation.statusMessage == "Connecting to NordicTrack...")

        presentation.markConnected(name: "NordicTrack")
        #expect(!presentation.isConnecting)
        #expect(presentation.isConnected)
        #expect(presentation.isLoading)
        #expect(presentation.connectedDeviceName == "NordicTrack")
        #expect(presentation.statusMessage == "Connected to NordicTrack. Discovering controls...")

        presentation.markControlsReady(name: "NordicTrack", controlPointReady: true)
        #expect(!presentation.isLoading)
        #expect(presentation.statusMessage == "Connected to NordicTrack. Controls are ready.")
    }

    @Test func bluetoothAvailabilityMessagesMatchState() {
        #expect(
            FTMSConnectionPresentation.bluetoothUnavailableMessage(for: .poweredOff)
                == "Turn Bluetooth on to search for treadmills."
        )
        #expect(
            FTMSConnectionPresentation.bluetoothUnavailableMessage(for: .unauthorized)
                == "Bluetooth permission is required to find treadmills."
        )
        #expect(
            FTMSConnectionPresentation.bluetoothUnavailableMessage(for: .unsupported)
                == "Bluetooth FTMS is not supported on this device."
        )
        #expect(
            FTMSConnectionPresentation.bluetoothUnavailableMessage(for: .unknown)
                == "Looking for treadmills"
        )
    }
}
