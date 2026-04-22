//
//  FTMSConnectionPresentation.swift
//  FTMSDemo
//
//  Created by Codex on 22/04/26.
//

import Foundation
import CoreBluetooth

struct DiscoveredTreadmill: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
}

struct FTMSConnectionPresentation: Equatable {
    var statusMessage = "Looking for threadmills"
    var isLoading = false
    var isScanning = false
    var isConnecting = false
    var isConnected = false
    var connectedDeviceName: String?
    var discoveredTreadmills: [DiscoveredTreadmill] = []
    var selectedTreadmillID: UUID?

    mutating func beginScanning() {
        discoveredTreadmills = []
        selectedTreadmillID = nil
        isLoading = true
        isScanning = true
        isConnecting = false
        isConnected = false
        connectedDeviceName = nil
        statusMessage = "Looking for threadmills"
    }

    mutating func addOrUpdateDiscoveredTreadmill(id: UUID, name: String, rssi: Int) {
        let treadmill = DiscoveredTreadmill(id: id, name: name, rssi: rssi)

        if let index = discoveredTreadmills.firstIndex(where: { $0.id == id }) {
            discoveredTreadmills[index] = treadmill
        } else {
            discoveredTreadmills.append(treadmill)
        }

        discoveredTreadmills.sort { $0.rssi > $1.rssi }
        statusMessage = discoveredTreadmills.count == 1
            ? "1 treadmill found nearby."
            : "\(discoveredTreadmills.count) treadmills found nearby."
    }

    mutating func beginConnecting(to treadmillID: UUID, name: String) {
        selectedTreadmillID = treadmillID
        isLoading = true
        isScanning = false
        isConnecting = true
        isConnected = false
        connectedDeviceName = nil
        statusMessage = "Connecting to \(name)..."
    }

    mutating func markConnected(name: String) {
        isConnecting = false
        isConnected = true
        isLoading = true
        isScanning = false
        connectedDeviceName = name
        statusMessage = "Connected to \(name). Discovering controls..."
    }

    mutating func markControlsReady(name: String, controlPointReady: Bool) {
        isLoading = false
        statusMessage = controlPointReady
            ? "Connected to \(name). Controls are ready."
            : "Connected to \(name). Waiting for treadmill data..."
    }

    mutating func markConnectionFailed(name: String) {
        isLoading = false
        isConnecting = false
        selectedTreadmillID = nil
        statusMessage = "Could not connect to \(name)."
    }

    mutating func beginDisconnecting(name: String) {
        isLoading = false
        isScanning = false
        statusMessage = "Disconnecting from \(name)..."
    }

    mutating func markDisconnected(name: String, didLoseConnection: Bool) {
        isLoading = false
        isScanning = false
        isConnecting = false
        isConnected = false
        connectedDeviceName = nil
        selectedTreadmillID = nil
        statusMessage = didLoseConnection
            ? "Connection to \(name) was lost."
            : "Disconnected from \(name)."
    }

    mutating func applyBluetoothState(_ state: CBManagerState) {
        isLoading = false
        isScanning = false
        isConnecting = false
        isConnected = false
        connectedDeviceName = nil
        selectedTreadmillID = nil
        statusMessage = Self.bluetoothUnavailableMessage(for: state)
    }

    static func bluetoothUnavailableMessage(for state: CBManagerState) -> String {
        switch state {
        case .unauthorized:
            return "Bluetooth permission is required to find treadmills."
        case .poweredOff:
            return "Turn Bluetooth on to search for treadmills."
        case .unsupported:
            return "Bluetooth FTMS is not supported on this device."
        case .resetting:
            return "Bluetooth is resetting. Please wait a moment."
        default:
            return "Looking for threadmills"
        }
    }
}
