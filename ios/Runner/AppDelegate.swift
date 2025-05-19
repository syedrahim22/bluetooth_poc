import UIKit
import Flutter
import CoreBluetooth
import CoreLocation

@UIApplicationMain
class AppDelegate: FlutterAppDelegate, CBPeripheralManagerDelegate, CBCentralManagerDelegate {
    // BLE properties
    private var peripheralManager: CBPeripheralManager?
    private var centralManager: CBCentralManager?
    private let peripheralQueue = DispatchQueue(label: "com.yourdomain.bleadvertiser.peripheral")
    private let centralQueue = DispatchQueue(label: "com.yourdomain.bleadvertiser.central")
    private var deviceUuid: String?
    private var scanResultsSink: FlutterEventSink?
    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Initialize Flutter - ensure proper plugin registration
        GeneratedPluginRegistrant.register(with: self)
        
        // Get the Flutter view controller
        guard let controller = window?.rootViewController as? FlutterViewController else {
            return super.application(application, didFinishLaunchingWithOptions: launchOptions)
        }
        
        // Set up method channel
        methodChannel = FlutterMethodChannel(
            name: "ble_advertiser",
            binaryMessenger: controller.binaryMessenger)
        
        // Set up event channel for scan results
        eventChannel = FlutterEventChannel(
            name: "ble_advertiser_scan_results", 
            binaryMessenger: controller.binaryMessenger)
        
        // Initialize BLE managers
        self.peripheralManager = CBPeripheralManager(delegate: self, queue: peripheralQueue)
        self.centralManager = CBCentralManager(delegate: self, queue: centralQueue)
        
        // Handle method calls
        methodChannel?.setMethodCallHandler { [weak self] (call, result) in
            guard let self = self else { return }
            
            switch call.method {
            case "startAdvertising":
                guard let args = call.arguments as? [String: Any],
                      let serviceUuid = args["serviceUuid"] as? String else {
                    result(FlutterError(code: "INVALID_ARGUMENT", message: "Service UUID is required", details: nil))
                    return
                }
                self.deviceUuid = serviceUuid
                self.startAdvertising(serviceUuid: serviceUuid)
                result(true)
                
            case "stopAdvertising":
                self.stopAdvertising()
                result(true)
                
            case "startScanning":
                self.startScanning()
                result(true)
                
            case "stopScanning":
                self.stopScanning()
                result(true)
                
            case "isBluetoothEnabled":
                let isEnabled = self.peripheralManager?.state == .poweredOn
                result(isEnabled)
                
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        
        // Set stream handler for event channel
        eventChannel?.setStreamHandler(ScanResultsStreamHandler(appDelegate: self))
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    // MARK: - BLE Methods
    
    private func startAdvertising(serviceUuid: String) {
        peripheralQueue.async { [weak self] in
            guard let self = self, 
                  let peripheralManager = self.peripheralManager,
                  peripheralManager.state == .poweredOn else {
                return
            }
            
            peripheralManager.stopAdvertising()
            
            guard let uuid = UUID(uuidString: serviceUuid) else {
                NSLog("Invalid UUID format")
                return
            }
            
            let serviceUuid = CBUUID(nsuuid: uuid)
            let advertisementData = [CBAdvertisementDataServiceUUIDsKey: [serviceUuid]]
            peripheralManager.startAdvertising(advertisementData)
            NSLog("Started advertising with UUID: \(serviceUuid)")
        }
    }
    
    private func stopAdvertising() {
        peripheralQueue.async { [weak self] in
            self?.peripheralManager?.stopAdvertising()
            NSLog("Stopped advertising")
        }
    }
    
    private func startScanning() {
        centralQueue.async { [weak self] in
            guard let self = self,
                  let centralManager = self.centralManager,
                  centralManager.state == .poweredOn else {
                return
            }
            
            // Scan for all services
            centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            NSLog("Started scanning for BLE devices")
        }
    }
    
    private func stopScanning() {
        centralQueue.async { [weak self] in
            self?.centralManager?.stopScan()
            NSLog("Stopped scanning")
        }
    }
    
    // MARK: - Delegate Methods
    
    // CBPeripheralManagerDelegate
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        NSLog("Peripheral manager state changed: \(peripheral.state.rawValue)")
        
        if peripheral.state == .poweredOn, let deviceUuid = self.deviceUuid {
            startAdvertising(serviceUuid: deviceUuid)
        }
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            NSLog("Failed to start advertising: \(error.localizedDescription)")
        } else {
            NSLog("Successfully started advertising")
        }
    }
    
    // CBCentralManagerDelegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        NSLog("Central manager state changed: \(central.state.rawValue)")
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        guard let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] else {
            return
        }
        
        let deviceName = peripheral.name ?? "Unknown"
        
        // Report back to Flutter through the event sink
        DispatchQueue.main.async { [weak self] in
            guard let scanResultsSink = self?.scanResultsSink else { return }
            
            for serviceUUID in serviceUUIDs {
                let result: [String: Any] = [
                    "deviceId": peripheral.identifier.uuidString,
                    "deviceName": deviceName,
                    "serviceUuid": serviceUUID.uuidString,
                    "rssi": RSSI.intValue
                ]
                scanResultsSink(result)
            }
        }
    }
    
    // Setter for event sink
    func setScanResultsSink(_ sink: FlutterEventSink?) {
        self.scanResultsSink = sink
    }
}

// Stream handler for scan results
class ScanResultsStreamHandler: NSObject, FlutterStreamHandler {
    private weak var appDelegate: AppDelegate?
    
    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        super.init()
    }
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        appDelegate?.setScanResultsSink(events)
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        appDelegate?.setScanResultsSink(nil)
        return nil
    }
}