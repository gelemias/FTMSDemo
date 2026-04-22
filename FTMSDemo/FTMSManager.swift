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
    @Published var statusMessage: String = "Idle" {
        didSet {
            print(statusMessage)
        }
    }
    
    @Published var isLoading: Bool = false

    private var central: CBCentralManager!

    private var treadmill: CBPeripheral?

    // FTMS
    private let ftmsServiceUUID = CBUUID(string: "1826")
    private let treadmillDataUUID = CBUUID(string: "2ACD")
    private let fitnessControlPointUUID = CBUUID(string: "2AD9")

    private var treadmillDataCharacteristic: CBCharacteristic?
    private var controlPointCharacteristic: CBCharacteristic?
    
    var controlPointReady: Bool {
        return controlPointCharacteristic != nil && treadmill != nil
    }

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScan() {
        guard central.state == .poweredOn else {
            statusMessage = "Bluetooth not powered on"
            return
        }

        isLoading = true

        central.scanForPeripherals(
            withServices: [ftmsServiceUUID],
            options: nil
        )

        statusMessage = "🔍 Scanning for FTMS"
    }
    
    func parseTreadmillData(_ data: Data) {
        var cursor = 0
        
        func readUInt16() -> UInt16 {
            defer { cursor += 2 }
            return UInt16(littleEndian:
                data.subdata(in: cursor..<cursor+2).withUnsafeBytes { $0.load(as: UInt16.self) }
            )
        }
        
        func readUInt24() -> UInt32 {
            // 3-byte little-endian
            let b0 = UInt32(data[cursor])
            let b1 = UInt32(data[cursor + 1]) << 8
            let b2 = UInt32(data[cursor + 2]) << 16
            cursor += 3
            return b0 | b1 | b2
        }

        // Flags (2 bytes)
        let flags = readUInt16()
        print("FTMS Flags: \(String(flags, radix: 2))")

        let speedPresent    = (flags & 0b0000000000000001) != 0
        let distancePresent = (flags & 0b0000000000000100) != 0   // 3 bytes
        let inclinePresent  = (flags & 0b0000000000001000) != 0
        let hrPresent       = (flags & 0b0000010000000000) != 0

        var new = TreadmillData()

        // 0.01 km/h
        if speedPresent {
            let raw = readUInt16()
            new.speedKmh = Double(raw) / 100.0
        }

        // Ignore avg speed (usually unused)

        // 3-byte distance (meters)
        if distancePresent {
            let raw = readUInt24()
            new.distanceMeters = Double(raw)
        }

        // Incline: 0.1% per unit
        if inclinePresent {
            let raw = readUInt16()
            new.incline = Double(Int16(bitPattern: raw)) / 10.0
        }

        if hrPresent {
            new.heartRate = Int(data[cursor])
            cursor += 1
        }

        DispatchQueue.main.async {
            self.treadmillData = new
        }
    }
    
    func handleControlPointResponse(_ data: Data) {
        guard data.count >= 3 else { return }

        let requestOpcode  = data[1]   // the opcode you sent
        let resultCode     = data[2]   // 1 = success

        switch resultCode {
        case 0x01:
            statusMessage = "✅ FTMS OK (opcode \(requestOpcode))"
        case 0x02:
            statusMessage = "⚠️ Not supported"
        case 0x03:
            statusMessage = "🚫 Invalid parameter"
        case 0x04:
            statusMessage = "❌ Operation failed"
        default:
            statusMessage = "❓ Unknown response"
        }
    }
}

extension FTMSManager {

    func requestControl() {
        sendControlPoint(opcode: 0x00)  // Request Control
        statusMessage = "⚙️ Requesting control"
    }

    func startTreadmill() {
        guard controlPointReady else {
            statusMessage = "⚠️ Control Point not available"
            return
        }

        // FTMS spec: Must request control first
        requestControl()

        // Start/Resume = 0x07
        sendControlPoint(opcode: 0x07)
        statusMessage = "▶️ Start sent"
    }

    func stopTreadmill() {
        guard controlPointReady else {
            statusMessage = "⚠️ Control Point not available"
            return
        }

        // Stop = 0x08
        sendControlPoint(opcode: 0x08)
        statusMessage = "⏹ Stop sent"
    }

    func sendTargetSpeed(kmh: Double) {
        guard controlPointReady else {
            statusMessage = "⚠️ Control Point not available"
            return
        }

        // FTMS speed = 0.01 m/s → but many treadmills also accept 0.01 km/h
        let value = UInt16(kmh * 100)

        let packet: [UInt8] = [
            0x02,                        // Set Target Speed opcode
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF)
        ]

        treadmill?.writeValue(Data(packet), for: controlPointCharacteristic!, type: .withResponse)
        statusMessage = "🎯 Speed set to \(kmh) km/h"
    }

    private func sendControlPoint(opcode: UInt8) {
        guard let cp = controlPointCharacteristic,
              let treadmill = treadmill else {
            statusMessage = "⚠️ Control Point not available"
            return
        }

        let packet = Data([opcode])
        treadmill.writeValue(packet, for: cp, type: .withResponse)
    }
}


extension FTMSManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScan()
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {

        statusMessage = "🏃 Found treadmill: \(peripheral.name ?? "?")"
        isLoading = false

        treadmill = peripheral
        treadmill?.delegate = self
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager,
                        didConnect peripheral: CBPeripheral) {

        statusMessage = "✅ Connected: \(peripheral.name ?? "?")"

        if peripheral == treadmill {
            peripheral.discoverServices([ftmsServiceUUID])
        }
    }
}

extension FTMSManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }

        for service in services {
            if service.uuid == ftmsServiceUUID {
                peripheral.discoverCharacteristics([treadmillDataUUID, fitnessControlPointUUID], for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {

        service.characteristics?.forEach { characteristic in
            switch characteristic.uuid {
            case treadmillDataUUID:
                treadmillDataCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                statusMessage = "👟 Treadmill Data ready"
            case fitnessControlPointUUID:
                controlPointCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                statusMessage = "🎛️ Control Point ready"
            default: break
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        print("Notify state for \(characteristic.uuid): \(characteristic.isNotifying), error: \(String(describing: error))")
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let data = characteristic.value else { return }
        
        if characteristic.uuid == fitnessControlPointUUID {
            handleControlPointResponse(data)
            return
        }

        
        if characteristic.uuid == treadmillDataUUID {
            parseTreadmillData(data)
            return
        }
    }
}
