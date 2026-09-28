import Combine
import Foundation

@MainActor
final class ConnectionViewModel: ObservableObject {
    private let manager: FTMSManager
    private var managerSubscription: AnyCancellable?

    init(manager: FTMSManager? = nil) {
        self.manager = manager ?? FTMSManager()
        managerSubscription = self.manager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var treadmillData: TreadmillData { manager.treadmillData }
    var statusMessage: String { manager.statusMessage }
    var isLoading: Bool { manager.isLoading }
    var isScanning: Bool { manager.isScanning }
    var isConnecting: Bool { manager.isConnecting }
    var isConnected: Bool { manager.isConnected }
    var connectedDeviceName: String? { manager.connectedDeviceName }
    var discoveredTreadmills: [DiscoveredTreadmill] { manager.discoveredTreadmills }
    var selectedTreadmillID: UUID? { manager.selectedTreadmillID }
    var controlPointReady: Bool { manager.controlPointReady }

    func startScan() { manager.startScan() }
    func connect(to treadmillID: UUID) { manager.connect(to: treadmillID) }
    func disconnect() { manager.disconnect() }
    func startTreadmill() { manager.startTreadmill() }
    func stopTreadmill() { manager.stopTreadmill() }
    func sendTargetSpeed(kmh: Double) { manager.sendTargetSpeed(kmh: kmh) }
}
