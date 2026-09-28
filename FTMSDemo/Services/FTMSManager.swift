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
    @Published var statusMessage: String = "Looking for treadmills" {
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
    private let dataParser = FTMSDataParser()

    var controlPointReady: Bool {
        controlPointCharacteristic != nil && treadmill != nil && isConnected
    }

    override init() {
        super.init()
        central = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "com.gelemias.dev.FTMSDemo.central"]
        )
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
        guard let parsedData = dataParser.parse(data) else { return }

        DispatchQueue.main.async {
            self.treadmillData = parsedData
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

        treadmill?.writeValue(FTMSCommandEncoder.targetSpeed(kmh: kmh), for: controlPointCharacteristic!, type: .withResponse)
        statusMessage = "Target speed set to \(kmh) km/h."
    }

    private func sendControlPoint(opcode: UInt8) {
        guard let cp = controlPointCharacteristic,
              let treadmill else {
            statusMessage = "Treadmill controls are not ready yet."
            return
        }

        treadmill.writeValue(FTMSCommandEncoder.controlPoint(opcode: opcode), for: cp, type: .withResponse)
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
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        guard let restoredPeripheral = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
              let peripheral = restoredPeripheral.first else { return }

        treadmill = peripheral
        peripheral.delegate = self
        if central.state == .poweredOn {
            peripheral.discoverServices([ftmsServiceUUID])
        }
    }

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
