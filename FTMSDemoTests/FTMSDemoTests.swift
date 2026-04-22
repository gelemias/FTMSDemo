//
//  FTMSDemoTests.swift
//  FTMSDemoTests
//
//  Created by DELGADO Guillermo on 22/4/26.
//

import CoreBluetooth
import Testing
@testable import FTMSDemo

struct FTMSDemoTests {

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
        #expect(presentation.statusMessage == "Looking for threadmills")
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
                == "Looking for threadmills"
        )
    }
}
