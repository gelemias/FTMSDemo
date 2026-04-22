//
//  FTMSManager.swift
//  FTMSDemo
//
//  Created by DELGADO Guillermo on 15/11/25.
//

import Foundation
import CoreBluetooth
import Combine

class FTMSManager: NSObject, ObservableObject {

    @Published var treadmillData = TreadmillData()
    @Published var statusMessage: String = "Looking for threadmills" {
        didSet {
            print(statusMessage)
        }
    }
    @Published var isLoading = false
    @Published var isScanning = false
    @Published var isConnecting = false
    @Published var isConnected = false
    @Published var connectedDeviceName: String?
    @Published var discoveredTreadmills: [DiscoveredTreadmill] = []
    @Published var selectedTreadmillID: UUID?

    private var presentation = FTMSConnectionPresentation() {
        didSet {
            publishPresentation()
        }
    }

    private var central: CBCentralManager!
    private var treadmill: CBPeripheral?
    private var discoveredPeripheralMap: [UUID: CBPeripheral] = [:]

    // FTMS
    private let ftmsServiceUUID = CBUUID(string: "1826")
    private let treadmillDataUUID = CBUUID(string: "2ACD")
    private let fitnessControlPointUUID = CBUUID(string: "2AD9")

    private var treadmillDataCharacteristic: CBCharacteristic?
    private var controlPointCharacteristic: CBCharacteristic?

    var controlPointReady: Bool {
        controlPointCharacteristic != nil && treadmill != nil && isConnected
    }

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        publishPresentation()
    }

    func startScan() {
        guard central.state == .poweredOn else {
            statusMessage = FTMSConnectionPresentation.bluetoothUnavailableMessage(for: central.state)
            return
        }

        guard !isConnecting else {
            return
        }

        resetDiscovery()
        presentation.beginScanning()

        central.scanForPeripherals(
            withServices: [ftmsServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func connect(to treadmillID: UUID) {
        guard central.state == .poweredOn else {
            statusMessage = FTMSConnectionPresentation.bluetoothUnavailableMessage(for: central.state)
            return
        }

        guard let peripheral = discoveredPeripheralMap[treadmillID] else {
            statusMessage = "That treadmill is no longer available."
            return
        }

        cleanupConnectionState()
        treadmill = peripheral
        treadmill?.delegate = self
        stopScan()

        let name = displayName(for: peripheral)
        presentation.beginConnecting(to: treadmillID, name: name)
        central.connect(peripheral)
    }

    func disconnect() {
        stopScan()
        isLoading = false

        guard let treadmill else {
            cleanupConnectionState()
            startScan()
            return
        }

        presentation.beginDisconnecting(name: displayName(for: treadmill))
        central.cancelPeripheralConnection(treadmill)
    }

    func parseTreadmillData(_ data: Data) {
        var cursor = 0
        
        func canRead(_ count: Int) -> Bool {
            cursor + count <= data.count
        }
        
        func readUInt8() -> UInt8? {
            guard canRead(1) else { return nil }
            defer { cursor += 1 }
            return data[cursor]
        }
        
        func readUInt16() -> UInt16? {
            guard canRead(2) else { return nil }
            defer { cursor += 2 }
            let low = UInt16(data[cursor])
            let high = UInt16(data[cursor + 1]) << 8
            return low | high
        }
        
        func readUInt24() -> UInt32? {
            guard canRead(3) else { return nil }
            let b0 = UInt32(data[cursor])
            let b1 = UInt32(data[cursor + 1]) << 8
            let b2 = UInt32(data[cursor + 2]) << 16
            cursor += 3
            return b0 | b1 | b2
        }
        
        @discardableResult
        func skip(_ count: Int) -> Bool {
            guard canRead(count) else { return false }
            cursor += count
            return true
        }
        
        guard let flags = readUInt16() else { return }
        
        // FTMS treadmill data: instantaneous speed is always present directly after flags.
        guard let rawSpeed = readUInt16() else { return }
        
        let avgSpeedPresent = (flags & (1 << 1)) != 0
        let totalDistancePresent = (flags & (1 << 2)) != 0
        let inclinePresent = (flags & (1 << 3)) != 0
        let elevationGainPresent = (flags & (1 << 4)) != 0
        let instantPacePresent = (flags & (1 << 5)) != 0
        let averagePacePresent = (flags & (1 << 6)) != 0
        let expendedEnergyPresent = (flags & (1 << 7)) != 0
        let heartRatePresent = (flags & (1 << 8)) != 0
        let metabolicEquivalentPresent = (flags & (1 << 9)) != 0
        let elapsedTimePresent = (flags & (1 << 10)) != 0
        let remainingTimePresent = (flags & (1 << 11)) != 0
        let forceOnBeltPresent = (flags & (1 << 12)) != 0
        
        var new = TreadmillData()
        new.speedKmh = Double(rawSpeed) / 100.0
        
        if avgSpeedPresent {
            _ = skip(2)
        }
        
        if totalDistancePresent, let rawDistance = readUInt24() {
            new.distanceMeters = Double(rawDistance)
        }
        
        if inclinePresent {
            if let rawIncline = readUInt16() {
                new.incline = Double(Int16(bitPattern: rawIncline)) / 10.0
            }
            _ = skip(2) // Ramp angle
        }
        
        if elevationGainPresent {
            _ = skip(4) // Positive and negative elevation gain
        }
        
        if instantPacePresent, let rawPace = readUInt16() {
            new.paceMinPerKm = Double(rawPace) / 10.0
        }
        
        if averagePacePresent {
            _ = skip(2)
        }
        
        if expendedEnergyPresent {
            _ = skip(5) // Total, per hour, per minute
        }
        
        if heartRatePresent, let hr = readUInt8() {
            new.heartRate = Int(hr)
        }
        
        if metabolicEquivalentPresent {
            _ = skip(1)
        }
        
        if elapsedTimePresent {
            _ = skip(2)
        }
        
        if remainingTimePresent {
            _ = skip(2)
        }
        
        if forceOnBeltPresent {
            _ = skip(4)
        }
        
        if new.paceMinPerKm == nil, let speed = new.speedKmh, speed > 0 {
            new.paceMinPerKm = 60.0 / speed
        }
        
        if let pace = new.paceMinPerKm, pace > 0 {
            let metersPerMinute = 1000.0 / pace
            new.cadenceSpm = Int((metersPerMinute / 1.0).rounded()) // Estimated using 1 m step length.
        }
        
        DispatchQueue.main.async {
            self.treadmillData = new
        }
    }

    func handleControlPointResponse(_ data: Data) {
        guard data.count >= 3 else { return }

        let requestOpcode = data[1]
        let resultCode = data[2]

        switch resultCode {
        case 0x01:
            statusMessage = "FTMS command accepted (opcode \(requestOpcode))."
        case 0x02:
            statusMessage = "That command is not supported by the treadmill."
        case 0x03:
            statusMessage = "The treadmill rejected that parameter."
        case 0x04:
            statusMessage = "The treadmill could not complete that operation."
        default:
            statusMessage = "Received an unknown response from the treadmill."
        }
    }
}

extension FTMSManager {

    func requestControl() {
        sendControlPoint(opcode: 0x00)
        statusMessage = "Requesting treadmill control..."
    }

    func startTreadmill() {
        guard controlPointReady else {
            statusMessage = "Treadmill controls are not ready yet."
            return
        }

        requestControl()
        sendControlPoint(opcode: 0x07)
        statusMessage = "Start command sent."
    }

    func stopTreadmill() {
        guard controlPointReady else {
            statusMessage = "Treadmill controls are not ready yet."
            return
        }

        sendControlPoint(opcode: 0x08)
        statusMessage = "Stop command sent."
    }

    func sendTargetSpeed(kmh: Double) {
        guard controlPointReady else {
            statusMessage = "Treadmill controls are not ready yet."
            return
        }

        let value = UInt16(kmh * 100)
        let packet: [UInt8] = [
            0x02,
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF)
        ]

        treadmill?.writeValue(Data(packet), for: controlPointCharacteristic!, type: .withResponse)
        statusMessage = "Target speed set to \(kmh) km/h."
    }

    private func sendControlPoint(opcode: UInt8) {
        guard let cp = controlPointCharacteristic,
              let treadmill else {
            statusMessage = "Treadmill controls are not ready yet."
            return
        }

        treadmill.writeValue(Data([opcode]), for: cp, type: .withResponse)
    }

    private func stopScan() {
        if central.isScanning {
            central.stopScan()
        }
        if presentation.isScanning {
            presentation.isScanning = false
        }
    }

    private func resetDiscovery() {
        discoveredPeripheralMap = [:]
    }

    private func cleanupConnectionState() {
        treadmillDataCharacteristic = nil
        controlPointCharacteristic = nil
        treadmillData = TreadmillData()
        treadmill = nil
    }

    private func displayName(for peripheral: CBPeripheral) -> String {
        let trimmedName = peripheral.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedName, !trimmedName.isEmpty {
            return trimmedName
        }
        return "FTMS Treadmill"
    }

    private func upsertDiscoveredTreadmill(_ peripheral: CBPeripheral, rssi: Int) {
        discoveredPeripheralMap[peripheral.identifier] = peripheral
        presentation.addOrUpdateDiscoveredTreadmill(
            id: peripheral.identifier,
            name: displayName(for: peripheral),
            rssi: rssi
        )
    }

    private func publishPresentation() {
        statusMessage = presentation.statusMessage
        isLoading = presentation.isLoading
        isScanning = presentation.isScanning
        isConnecting = presentation.isConnecting
        isConnected = presentation.isConnected
        connectedDeviceName = presentation.connectedDeviceName
        discoveredTreadmills = presentation.discoveredTreadmills
        selectedTreadmillID = presentation.selectedTreadmillID
    }
}

extension FTMSManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        stopScan()

        guard central.state == .poweredOn else {
            cleanupConnectionState()
            presentation.applyBluetoothState(central.state)
            return
        }

        if !isConnected {
            startScan()
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {

        upsertDiscoveredTreadmill(peripheral, rssi: RSSI.intValue)
    }

    func centralManager(_ central: CBCentralManager,
                        didConnect peripheral: CBPeripheral) {

        presentation.markConnected(name: displayName(for: peripheral))

        if peripheral == treadmill {
            peripheral.discoverServices([ftmsServiceUUID])
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        treadmill = nil
        presentation.markConnectionFailed(name: displayName(for: peripheral))
        startScan()
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        let name = displayName(for: peripheral)
        cleanupConnectionState()
        presentation.markDisconnected(name: name, didLoseConnection: error != nil)
        startScan()
    }
}

extension FTMSManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            statusMessage = "Could not load treadmill services: \(error.localizedDescription)"
            isLoading = false
            return
        }

        guard let services = peripheral.services else { return }

        for service in services where service.uuid == ftmsServiceUUID {
            peripheral.discoverCharacteristics([treadmillDataUUID, fitnessControlPointUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {

        if let error {
            statusMessage = "Could not load treadmill controls: \(error.localizedDescription)"
            isLoading = false
            return
        }

        service.characteristics?.forEach { characteristic in
            switch characteristic.uuid {
            case treadmillDataUUID:
                treadmillDataCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            case fitnessControlPointUUID:
                controlPointCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            default:
                break
            }
        }

        presentation.markControlsReady(
            name: displayName(for: peripheral),
            controlPointReady: controlPointReady
        )
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        print("Notify state for \(characteristic.uuid): \(characteristic.isNotifying), error: \(String(describing: error))")
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard error == nil, let data = characteristic.value else { return }

        if characteristic.uuid == fitnessControlPointUUID {
            handleControlPointResponse(data)
            return
        }

        if characteristic.uuid == treadmillDataUUID {
            parseTreadmillData(data)
        }
    }
}
