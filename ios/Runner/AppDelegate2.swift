// import CoreBluetooth
// import UIKit
// import Flutter
// import CoreLocation
// import BackgroundTasks

//  // Implement CBPeripheralDelegate to read the characteristic
//     extension AppDelegate: CBPeripheralDelegate {

//         func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
//             NSLog("✅ Connected to peripheral: \(peripheral.name ?? "Unknown")")

//             // Discover the service
//             if let serviceUUID = peripheral.services?.first?.uuid {
//                 peripheral.discoverServices([serviceUUID])
//             } else {
//                 peripheral.discoverServices(nil) // Discover all services
//             }
//         }

//         func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
//             if let error = error {
//                 NSLog("❌ Error discovering services: \(error)")
//                 return
//             }

//             guard let services = peripheral.services else { return }

//             for service in services {
//                 NSLog("🔍 Discovered service: \(service.uuid)")
//                 // Look for our characteristic
//                 let characteristicUUID = CBUUID(string: "12345678-1234-1234-1234-123456789ABC")
//                 peripheral.discoverCharacteristics([characteristicUUID], for: service)
//             }
//         }

//         func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
//             if let error = error {
//                 NSLog("❌ Error discovering characteristics: \(error)")
//                 return
//             }

//             guard let characteristics = service.characteristics else { return }

//             for characteristic in characteristics {
//                 let targetUUID = CBUUID(string: "12345678-1234-1234-1234-123456789ABC")
//                 if characteristic.uuid == targetUUID {
//                     NSLog("📖 Reading UUID characteristic...")
//                     peripheral.readValue(for: characteristic)
//                 }
//             }
//         }

//         func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
//             if let error = error {
//                 NSLog("❌ Error reading characteristic: \(error)")
//                 return
//             }

//             let targetUUID = CBUUID(string: "12345678-1234-1234-1234-123456789ABC")
//             if characteristic.uuid == targetUUID,
//             let data = characteristic.value,
//             let fullUUID = String(data: data, encoding: .utf8) {

//                 NSLog("🎉 Got full UUID from background device: \(fullUUID)")

//                 // Send complete data to Flutter
//                 DispatchQueue.main.async { [weak self] in
//                     guard let scanResultsSink = self?.scanResultsSink else { return }

//                     let result: [String: Any] = [
//                         "deviceId": peripheral.identifier.uuidString,
//                         "deviceName": peripheral.name ?? "Unknown",
//                         "serviceUuid": characteristic.service?.uuid.uuidString ?? "",
//                         "rssi": 0, // RSSI not available after connection
//                         "extractedUuid": fullUUID,
//                         "hasManufacturerData": true,
//                         "isPartialData": false,
//                         "readFromGATT": true // Flag to indicate this came from GATT read
//                     ]
//                     scanResultsSink(result)
//                 }
//             }

//             // Disconnect after reading
//             centralManager?.cancelPeripheralConnection(peripheral)
//         }

//         func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
//             NSLog("🔌 Disconnected from peripheral: \(peripheral.name ?? "Unknown")")
//         }
//     }

// @UIApplicationMain
// class AppDelegate: FlutterAppDelegate, CBPeripheralManagerDelegate, CBCentralManagerDelegate, CLLocationManagerDelegate {
//     // BLE properties
//     private var peripheralManager: CBPeripheralManager?
//     private var centralManager: CBCentralManager?
//     private let peripheralQueue = DispatchQueue(label: "com.example.bluetoothPoc1.peripheral")
//     private let centralQueue = DispatchQueue(label: "com.example.bluetoothPoc1.central")
//     private var deviceUuid: String?
//     private var scanResultsSink: FlutterEventSink?
//     private var methodChannel: FlutterMethodChannel?
//     private var eventChannel: FlutterEventChannel?

//     // GATT Service properties for proper background advertising
//     private var customService: CBMutableService?
//     private var uuidCharacteristic: CBMutableCharacteristic?

//     // Background properties
//     private var locationManager: CLLocationManager?
//     private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
//     private var isAdvertisingInBackground = false
//     private var isScanningInBackground = false
//     private let restoreIdentifier = "com.example.bluetoothPoc1.restoreIdentifier"
//     private var backgroundTaskTimer: Timer?

//     override func application(
//         _ application: UIApplication,
//         didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
//     ) -> Bool {
//         // Initialize Flutter - ensure proper plugin registration
//         GeneratedPluginRegistrant.register(with: self)

//         // Get the Flutter view controller
//         guard let controller = window?.rootViewController as? FlutterViewController else {
//             return super.application(application, didFinishLaunchingWithOptions: launchOptions)
//         }

//         // Set up method channel
//         methodChannel = FlutterMethodChannel(
//             name: "ble_advertiser",
//             binaryMessenger: controller.binaryMessenger)

//         // Set up event channel for scan results
//         eventChannel = FlutterEventChannel(
//             name: "ble_advertiser_scan_results",
//             binaryMessenger: controller.binaryMessenger)

//         // Initialize location manager with proper setup
//         setupLocationManager()

//         // Initialize BLE managers with restoration identifiers for background operation
//         let peripheralOptions: [String: Any] = [
//             CBPeripheralManagerOptionRestoreIdentifierKey: "\(restoreIdentifier).peripheral",
//             CBPeripheralManagerOptionShowPowerAlertKey: true
//         ]
//         self.peripheralManager = CBPeripheralManager(delegate: self, queue: peripheralQueue, options: peripheralOptions)

//         let centralOptions: [String: Any] = [
//             CBCentralManagerOptionRestoreIdentifierKey: "\(restoreIdentifier).central",
//             CBCentralManagerScanOptionAllowDuplicatesKey: false
//         ]
//         self.centralManager = CBCentralManager(delegate: self, queue: centralQueue, options: centralOptions)

//         // Register background fetch task
//         BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.example.bluetoothPoc1.refresh", using: nil) { task in
//             self.handleBackgroundRefresh(task: task as! BGAppRefreshTask)
//         }

//         // Handle method calls
//         methodChannel?.setMethodCallHandler { [weak self] (call, result) in
//             guard let self = self else { return }

//             switch call.method {
//             case "startAdvertising":
//                 guard let args = call.arguments as? [String: Any],
//                       let serviceUuid = args["serviceUuid"] as? String else {
//                     result(FlutterError(code: "INVALID_ARGUMENT", message: "Service UUID is required", details: nil))
//                     return
//                 }
//                 let inBackground = args["inBackground"] as? Bool ?? false
//                 self.deviceUuid = serviceUuid
//                 self.startAdvertising(serviceUuid: serviceUuid, inBackground: inBackground)
//                 result(true)

//             case "stopAdvertising":
//                 self.stopAdvertising()
//                 result(true)

//             case "startScanning":
//                 let inBackground = (call.arguments as? [String: Any])?["inBackground"] as? Bool ?? false
//                 self.startScanning(inBackground: inBackground)
//                 result(true)

//             case "stopScanning":
//                 self.stopScanning()
//                 result(true)

//             case "isBluetoothEnabled":
//                 let isEnabled = self.peripheralManager?.state == .poweredOn
//                 result(isEnabled)

//             case "requestAlwaysLocationPermission":
//                 self.requestLocationPermission()
//                 result(true)

//             case "getBackgroundStatus":
//                 let status = self.checkBackgroundCapabilities()
//                 let response: [String: Any] = [
//                     "canRunInBackground": status.canRunInBackground,
//                     "reason": status.reason,
//                     "hasLocationPermission": status.canRunInBackground,
//                     "backgroundTimeRemaining": UIApplication.shared.backgroundTimeRemaining
//                 ]
//                 result(response)

//             default:
//                 result(FlutterMethodNotImplemented)
//             }
//         }

//         // Set stream handler for event channel
//         eventChannel?.setStreamHandler(ScanResultsStreamHandler(appDelegate: self))

//         // Schedule initial background task if app was launched due to BLE events
//         if launchOptions?[UIApplication.LaunchOptionsKey.bluetoothCentrals] != nil ||
//            launchOptions?[UIApplication.LaunchOptionsKey.bluetoothPeripherals] != nil {
//             scheduleBackgroundTasks()
//         }

//         return super.application(application, didFinishLaunchingWithOptions: launchOptions)
//     }

//     // MARK: - GATT Service Setup

//     private func setupGATTService(with serviceUuid: String) {
//         guard let serviceUUID = UUID(uuidString: serviceUuid) else {
//             NSLog("Invalid service UUID format")
//             return
//         }

//         let serviceCBUUID = CBUUID(nsuuid: serviceUUID)

//         // Create the service
//         customService = CBMutableService(type: serviceCBUUID, primary: true)

//         // Create a characteristic to hold the UUID data
//         let characteristicUUID = CBUUID(string: "12345678-1234-1234-1234-123456789ABC")
//         uuidCharacteristic = CBMutableCharacteristic(
//             type: characteristicUUID,
//             properties: [.read],
//             value: serviceUuid.data(using: .utf8), // ✅ Use the string data
//             permissions: [.readable]
//         )

//         // Add characteristic to service
//         customService?.characteristics = [uuidCharacteristic!]

//         NSLog("Created GATT service with UUID: \(serviceUuid)")
//     }

//     // MARK: - Location Manager Setup (keeping existing implementation)

//     private func setupLocationManager() {
//         self.locationManager = CLLocationManager()
//         self.locationManager?.delegate = self
//         self.locationManager?.desiredAccuracy = kCLLocationAccuracyThreeKilometers
//         self.locationManager?.distanceFilter = 1000

//         let authStatus: CLAuthorizationStatus
//         if #available(iOS 14.0, *) {
//             authStatus = locationManager?.authorizationStatus ?? .notDetermined
//         } else {
//             authStatus = CLLocationManager.authorizationStatus()
//         }

//         switch authStatus {
//         case .authorizedAlways:
//             configureLocationForBackground()
//         case .authorizedWhenInUse:
//             locationManager?.requestAlwaysAuthorization()
//         case .notDetermined:
//             locationManager?.requestWhenInUseAuthorization()
//         case .denied, .restricted:
//             NSLog("Location permission denied. Background functionality will be limited.")
//         @unknown default:
//             NSLog("Unknown location authorization status")
//         }
//     }

//     private func configureLocationForBackground() {
//         let authStatus: CLAuthorizationStatus
//         if #available(iOS 14.0, *) {
//             authStatus = locationManager?.authorizationStatus ?? .notDetermined
//         } else {
//             authStatus = CLLocationManager.authorizationStatus()
//         }

//         guard authStatus == .authorizedAlways else {
//             NSLog("Cannot configure background location without always authorization")
//             return
//         }

//         locationManager?.allowsBackgroundLocationUpdates = true
//         locationManager?.pausesLocationUpdatesAutomatically = false
//         NSLog("Configured location manager for background operation")
//     }

//     private func requestLocationPermission() {
//         guard let locationManager = locationManager else { return }

//         let authStatus: CLAuthorizationStatus
//         if #available(iOS 14.0, *) {
//             authStatus = locationManager.authorizationStatus
//         } else {
//             authStatus = CLLocationManager.authorizationStatus()
//         }

//         switch authStatus {
//         case .notDetermined:
//             locationManager.requestAlwaysAuthorization()
//         case .authorizedWhenInUse:
//             showAlwaysPermissionExplanation()
//         case .denied, .restricted:
//             showLocationPermissionAlert()
//         case .authorizedAlways:
//             NSLog("Already have always location permission")
//             configureLocationForBackground()
//         @unknown default:
//             break
//         }
//     }

//     private func showAlwaysPermissionExplanation() {
//         guard let controller = window?.rootViewController else { return }

//         let alert = UIAlertController(
//             title: "Background Access Needed",
//             message: "To maintain Bluetooth connectivity when the app is in the background, we need 'Always' location permission. This allows the app to continue discovering and communicating with devices even when not actively used.",
//             preferredStyle: .alert
//         )

//         alert.addAction(UIAlertAction(title: "Grant Always Access", style: .default) { _ in
//             self.locationManager?.requestAlwaysAuthorization()
//         })

//         alert.addAction(UIAlertAction(title: "Keep Current", style: .cancel) { _ in
//             NSLog("User chose to keep 'When In Use' permission - background functionality will be limited")
//         })

//         controller.present(alert, animated: true)
//     }

//     private func showLocationPermissionAlert() {
//         guard let controller = window?.rootViewController else { return }

//         let alert = UIAlertController(
//             title: "Location Permission Required",
//             message: "This app needs location permission to maintain Bluetooth connectivity in the background. Please enable 'Always' location access in Settings.",
//             preferredStyle: .alert
//         )

//         alert.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
//             if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
//                 UIApplication.shared.open(settingsUrl)
//             }
//         })

//         alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

//         controller.present(alert, animated: true)
//     }

//     // MARK: - Background Task Management (keeping existing implementation)

//     private func beginBackgroundTask() {
//         endBackgroundTask()

//         backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
//             NSLog("Background task is about to expire")
//             self?.handleBackgroundTaskExpiration()
//         }

//         backgroundTaskTimer = Timer.scheduledTimer(withTimeInterval: 25.0, repeats: false) { [weak self] _ in
//             NSLog("Proactively ending background task after 25 seconds")
//             self?.endBackgroundTask()
//         }

//         NSLog("Started background task: \(backgroundTask.rawValue)")
//     }

//     private func endBackgroundTask() {
//         backgroundTaskTimer?.invalidate()
//         backgroundTaskTimer = nil

//         if backgroundTask != .invalid {
//             NSLog("Ending background task: \(backgroundTask.rawValue)")
//             UIApplication.shared.endBackgroundTask(backgroundTask)
//             backgroundTask = .invalid
//         }
//     }

//     private func handleBackgroundTaskExpiration() {
//         NSLog("Background task expiring - stopping BLE operations")

//         if isAdvertisingInBackground {
//             stopAdvertising()
//         }
//         if isScanningInBackground {
//             stopScanning()
//         }

//         locationManager?.stopUpdatingLocation()
//         endBackgroundTask()
//     }

//     private func scheduleBackgroundTasks() {
//         let request = BGAppRefreshTaskRequest(identifier: "com.example.bluetoothPoc1.refresh")
//         request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

//         do {
//             try BGTaskScheduler.shared.submit(request)
//             NSLog("Background refresh task scheduled")
//         } catch {
//             NSLog("Could not schedule background tasks: \(error)")
//         }
//     }

//     private func handleBackgroundRefresh(task: BGAppRefreshTask) {
//         NSLog("Handling background refresh task")

//         scheduleBackgroundTasks()

//         let authStatus: CLAuthorizationStatus
//         if #available(iOS 14.0, *) {
//             authStatus = locationManager?.authorizationStatus ?? .notDetermined
//         } else {
//             authStatus = CLLocationManager.authorizationStatus()
//         }
//         let canUseLocation = authStatus == .authorizedAlways

//         if canUseLocation {
//             beginBackgroundTask()

//             if isAdvertisingInBackground, let deviceUuid = self.deviceUuid {
//                 startAdvertising(serviceUuid: deviceUuid, inBackground: true)
//             }

//             if isScanningInBackground {
//                 startScanning(inBackground: true)
//             }

//             if isAdvertisingInBackground || isScanningInBackground {
//                 locationManager?.startUpdatingLocation()
//             }
//         } else {
//             NSLog("Cannot use background location - limited background time available")
//         }

//         DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
//             task.setTaskCompleted(success: true)
//         }
//     }

//     // MARK: - Enhanced BLE Methods

//     private func startAdvertising(serviceUuid: String, inBackground: Bool = false) {
//         peripheralQueue.async { [weak self] in
//             guard let self = self,
//                   let peripheralManager = self.peripheralManager,
//                   peripheralManager.state == .poweredOn else {
//                 NSLog("Peripheral manager not ready")
//                 return
//             }

//             // Stop any existing advertising
//             peripheralManager.stopAdvertising()

//             // Remove existing services
//             peripheralManager.removeAllServices()

//             // Set up GATT service for background compatibility
//             self.setupGATTService(with: serviceUuid)

//             guard let customService = self.customService else {
//                 NSLog("Failed to create GATT service")
//                 return
//             }

//             // Add the service to peripheral manager
//             peripheralManager.add(customService)

//             // Wait a moment for service to be added, then start advertising
//             DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
//                 self.peripheralQueue.async {
//                     guard let uuid = UUID(uuidString: serviceUuid) else {
//                         NSLog("Invalid UUID format")
//                         return
//                     }

//                     let serviceCBUUID = CBUUID(nsuuid: uuid)

//                     // Create advertisement data
//                     var advertisementData: [String: Any] = [
//                         CBAdvertisementDataServiceUUIDsKey: [serviceCBUUID],
//                         CBAdvertisementDataLocalNameKey: "BLEDevice-\(serviceUuid.prefix(8))"
//                     ]

//                     // In foreground, we can add more data
//                     if !inBackground {
//                         // Add manufacturer data with the UUID
//                         let manufacturerData = Data(serviceUuid.utf8)
//                         advertisementData[CBAdvertisementDataManufacturerDataKey] = manufacturerData
//                     }

//                     self.isAdvertisingInBackground = inBackground

//                     // Start location updates for background operation
//                     let authStatus: CLAuthorizationStatus
//                     if #available(iOS 14.0, *) {
//                         authStatus = self.locationManager?.authorizationStatus ?? .notDetermined
//                     } else {
//                         authStatus = CLLocationManager.authorizationStatus()
//                     }

//                     if inBackground && authStatus == .authorizedAlways {
//                         DispatchQueue.main.async {
//                             self.locationManager?.startUpdatingLocation()
//                             self.beginBackgroundTask()
//                         }
//                     }

//                     // Start advertising
//                     peripheralManager.startAdvertising(advertisementData)
//                     NSLog("Started advertising with UUID: \(serviceCBUUID), background: \(inBackground)")
//                 }
//             }
//         }
//     }

//     // private func startAdvertising(serviceUuid: String, inBackground: Bool = false) {
//     //     peripheralQueue.async { [weak self] in
//     //         guard let self = self,
//     //             let peripheralManager = self.peripheralManager,
//     //             peripheralManager.state == .poweredOn else {
//     //             NSLog("Peripheral manager not ready")
//     //             return
//     //         }

//     //         // Stop any existing advertising
//     //         peripheralManager.stopAdvertising()
//     //         peripheralManager.removeAllServices()

//     //         // Set up GATT service for background compatibility
//     //         self.setupGATTService(with: serviceUuid)

//     //         guard let customService = self.customService else {
//     //             NSLog("Failed to create GATT service")
//     //             return
//     //         }

//     //         // Add the service to peripheral manager
//     //         peripheralManager.add(customService)

//     //         // Wait a moment for service to be added, then start advertising
//     //         DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
//     //             self.peripheralQueue.async {
//     //                 guard let uuid = UUID(uuidString: serviceUuid) else {
//     //                     NSLog("Invalid UUID format")
//     //                     return
//     //                 }

//     //                 let serviceCBUUID = CBUUID(nsuuid: uuid)

//     //                 // Create advertisement data with encoded UUID in name
//     //                 var advertisementData: [String: Any] = [
//     //                     CBAdvertisementDataServiceUUIDsKey: [serviceCBUUID]
//     //                 ]

//     //                 if inBackground {
//     //                     // Encode full UUID in device name for background (limited to 28 chars)
//     //                     let shortUuid = String(serviceUuid.prefix(28))  // Truncate if needed
//     //                     advertisementData[CBAdvertisementDataLocalNameKey] = "BLE-\(shortUuid)"
//     //                 } else {
//     //                     // In foreground, use both name and manufacturer data
//     //                     advertisementData[CBAdvertisementDataLocalNameKey] = "BLEDevice-\(serviceUuid.prefix(8))"
//     //                     let manufacturerData = Data(serviceUuid.utf8)
//     //                     advertisementData[CBAdvertisementDataManufacturerDataKey] = manufacturerData
//     //                 }

//     //                 self.isAdvertisingInBackground = inBackground

//     //                 // Start location updates for background operation
//     //                 let authStatus: CLAuthorizationStatus
//     //                 if #available(iOS 14.0, *) {
//     //                     authStatus = self.locationManager?.authorizationStatus ?? .notDetermined
//     //                 } else {
//     //                     authStatus = CLLocationManager.authorizationStatus()
//     //                 }

//     //                 if inBackground && authStatus == .authorizedAlways {
//     //                     DispatchQueue.main.async {
//     //                         self.locationManager?.startUpdatingLocation()
//     //                         self.beginBackgroundTask()
//     //                     }
//     //                 }

//     //                 // Start advertising
//     //                 peripheralManager.startAdvertising(advertisementData)
//     //                 NSLog("Started advertising with UUID: \(serviceCBUUID), background: \(inBackground)")
//     //             }
//     //         }
//     //     }
//     // }

//     private func stopAdvertising() {
//         peripheralQueue.async { [weak self] in
//             guard let self = self else { return }

//             self.peripheralManager?.stopAdvertising()
//             self.peripheralManager?.removeAllServices()
//             self.isAdvertisingInBackground = false

//             if !self.isScanningInBackground {
//                 DispatchQueue.main.async {
//                     self.locationManager?.stopUpdatingLocation()
//                     self.endBackgroundTask()
//                 }
//             }

//             NSLog("Stopped advertising")
//         }
//     }

//     private func startScanning(inBackground: Bool = false) {
//         centralQueue.async { [weak self] in
//             guard let self = self,
//                   let centralManager = self.centralManager,
//                   centralManager.state == .poweredOn else {
//                 NSLog("Central manager not ready")
//                 return
//             }

//             self.isScanningInBackground = inBackground

//             let authStatus: CLAuthorizationStatus
//             if #available(iOS 14.0, *) {
//                 authStatus = self.locationManager?.authorizationStatus ?? .notDetermined
//             } else {
//                 authStatus = CLLocationManager.authorizationStatus()
//             }

//             if inBackground && authStatus == .authorizedAlways {
//                 DispatchQueue.main.async {
//                     self.locationManager?.startUpdatingLocation()
//                     self.beginBackgroundTask()
//                 }
//             }

//             // Scan options - more restrictive in background to save battery
//             let scanOptions: [String: Any] = [
//                 CBCentralManagerScanOptionAllowDuplicatesKey: !inBackground
//             ]

//             // Start scanning for all services (nil) to catch all advertisements
//             centralManager.scanForPeripherals(withServices: nil, options: scanOptions)
//             NSLog("Started scanning for BLE devices, background: \(inBackground)")
//         }
//     }

//     private func stopScanning() {
//         centralQueue.async { [weak self] in
//             guard let self = self else { return }

//             self.centralManager?.stopScan()
//             self.isScanningInBackground = false

//             if !self.isAdvertisingInBackground {
//                 DispatchQueue.main.async {
//                     self.locationManager?.stopUpdatingLocation()
//                     self.endBackgroundTask()
//                 }
//             }

//             NSLog("Stopped scanning")
//         }
//     }

//     // MARK: - CLLocationManagerDelegate (keeping existing implementation)

//     func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
//         NSLog("Location authorization changed to: \(status.rawValue)")

//         switch status {
//         case .authorizedAlways:
//             NSLog("✅ Got 'Always' location permission - full background functionality available")
//             configureLocationForBackground()

//         case .authorizedWhenInUse:
//             NSLog("⚠️ Only have 'When In Use' permission - consider requesting 'Always' for background functionality")

//         case .denied:
//             NSLog("❌ Location permission denied - background functionality severely limited")
//             manager.stopUpdatingLocation()

//         case .restricted:
//             NSLog("❌ Location access restricted - background functionality not available")
//             manager.stopUpdatingLocation()

//         case .notDetermined:
//             NSLog("📍 Location permission not determined yet")

//         @unknown default:
//             NSLog("❓ Unknown location authorization status: \(status.rawValue)")
//         }

//         DispatchQueue.main.async {
//             self.methodChannel?.invokeMethod("onLocationPermissionChanged", arguments: [
//                 "status": status.rawValue,
//                 "canRunInBackground": status == .authorizedAlways
//             ])
//         }
//     }

//     func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
//         NSLog("Location updated in background - maintaining app state")
//     }

//     func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
//         let clError = error as? CLError
//         switch clError?.code {
//         case .denied:
//             NSLog("Location access denied - stopping location updates")
//             manager.stopUpdatingLocation()
//         case .locationUnknown:
//             NSLog("Location unknown - will keep trying")
//         case .network:
//             NSLog("Network error getting location")
//         default:
//             NSLog("Location manager error: \(error.localizedDescription)")
//         }
//     }

//     // MARK: - CBPeripheralManagerDelegate

//     func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
//         NSLog("Peripheral manager state changed: \(peripheral.state.rawValue)")

//         switch peripheral.state {
//         case .poweredOn:
//             NSLog("Bluetooth powered on - ready for operations")
//             if let deviceUuid = self.deviceUuid, isAdvertisingInBackground {
//                 startAdvertising(serviceUuid: deviceUuid, inBackground: true)
//             }
//         case .poweredOff:
//             NSLog("Bluetooth powered off")
//         case .unauthorized:
//             NSLog("Bluetooth unauthorized")
//         case .unsupported:
//             NSLog("Bluetooth unsupported")
//         case .resetting:
//             NSLog("Bluetooth resetting")
//         case .unknown:
//             NSLog("Bluetooth state unknown")
//         @unknown default:
//             NSLog("Unknown Bluetooth state")
//         }
//     }

//     func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
//         if let error = error {
//             NSLog("Failed to add service: \(error.localizedDescription)")
//         } else {
//             NSLog("Successfully added service: \(service.uuid)")
//         }
//     }

//     func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String : Any]) {
//         NSLog("Peripheral manager restoring state: \(dict)")

//         if let services = dict[CBPeripheralManagerRestoredStateServicesKey] as? [CBService],
//            let firstService = services.first {

//             self.deviceUuid = firstService.uuid.uuidString
//             self.isAdvertisingInBackground = true

//             DispatchQueue.main.async {
//                 let authStatus: CLAuthorizationStatus
//                 if #available(iOS 14.0, *) {
//                     authStatus = self.locationManager?.authorizationStatus ?? .notDetermined
//                 } else {
//                     authStatus = CLLocationManager.authorizationStatus()
//                 }

//                 if authStatus == .authorizedAlways {
//                     self.beginBackgroundTask()
//                     if let uuid = self.deviceUuid {
//                         self.startAdvertising(serviceUuid: uuid, inBackground: true)
//                     }
//                 }
//             }
//         }
//     }

//     func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
//         if let error = error {
//             NSLog("Failed to start advertising: \(error.localizedDescription)")
//         } else {
//             NSLog("Successfully started advertising")
//         }
//     }

//     func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
//         NSLog("Received read request for characteristic: \(request.characteristic.uuid)")

//         if request.characteristic.uuid == uuidCharacteristic?.uuid {
//             if let deviceUuid = self.deviceUuid,
//                let data = deviceUuid.data(using: .utf8) {
//                 request.value = data
//                 peripheral.respond(to: request, withResult: .success)
//                 NSLog("Responded to read request with UUID: \(deviceUuid)")
//             } else {
//                 peripheral.respond(to: request, withResult: .readNotPermitted)
//             }
//         } else {
//             peripheral.respond(to: request, withResult: .requestNotSupported)
//         }
//     }

//     // MARK: - CBCentralManagerDelegate

//     func centralManagerDidUpdateState(_ central: CBCentralManager) {
//         NSLog("Central manager state changed: \(central.state.rawValue)")

//         if central.state == .poweredOn && isScanningInBackground {
//             startScanning(inBackground: true)
//         }
//     }

//     func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
//         NSLog("Central manager restoring state: \(dict)")

//         if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
//             if !peripherals.isEmpty {
//                 self.isScanningInBackground = true

//                 DispatchQueue.main.async {
//                     let authStatus: CLAuthorizationStatus
//                     if #available(iOS 14.0, *) {
//                         authStatus = self.locationManager?.authorizationStatus ?? .notDetermined
//                     } else {
//                         authStatus = CLLocationManager.authorizationStatus()
//                     }

//                     if authStatus == .authorizedAlways {
//                         self.beginBackgroundTask()
//                         self.startScanning(inBackground: true)
//                     }
//                 }
//             }
//         }
//     }

//     // func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
//     //     let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
//     //     let deviceName = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown"

//     //     // Try to extract UUID from manufacturer data if available
//     //     var extractedUuid: String? = nil
//     //     if let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
//     //         extractedUuid = String(data: manufacturerData, encoding: .utf8)
//     //     }

//     //     DispatchQueue.main.async { [weak self] in
//     //         guard let scanResultsSink = self?.scanResultsSink else { return }

//     //         if serviceUUIDs.isEmpty {
//     //             let result: [String: Any] = [
//     //                 "deviceId": peripheral.identifier.uuidString,
//     //                 "deviceName": deviceName,
//     //                 "serviceUuid": extractedUuid ?? "",
//     //                 "rssi": RSSI.intValue,
//     //                 "hasManufacturerData": extractedUuid != nil
//     //             ]
//     //             scanResultsSink(result)
//     //         } else {
//     //             for serviceUUID in serviceUUIDs {
//     //                 let result: [String: Any] = [
//     //                     "deviceId": peripheral.identifier.uuidString,
//     //                     "deviceName": deviceName,
//     //                     "serviceUuid": serviceUUID.uuidString,
//     //                     "rssi": RSSI.intValue,
//     //                     "extractedUuid": extractedUuid ?? "",
//     //                     "hasManufacturerData": extractedUuid != nil
//     //                 ]
//     //                 scanResultsSink(result)
//     //             }
//     //         }
//     //     }
//     // }

//     func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
//         let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
//         let deviceName = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown"

//         // Check if this looks like our device
//         let isOurDevice = deviceName.hasPrefix("BLEDevice-") || !serviceUUIDs.isEmpty

//         if isOurDevice && !serviceUUIDs.isEmpty {
//             // For background-discovered devices, connect to read the full UUID
//             NSLog("🔍 Discovered potential device in background: \(deviceName)")
//             NSLog("🔗 Connecting to read full UUID...")

//             peripheral.delegate = self // Make sure to implement CBPeripheralDelegate
//             central.connect(peripheral, options: nil)
//         }

//         // Still send partial data immediately for quick discovery
//         DispatchQueue.main.async { [weak self] in
//             guard let scanResultsSink = self?.scanResultsSink else { return }

//             if serviceUUIDs.isEmpty {
//                 let result: [String: Any] = [
//                     "deviceId": peripheral.identifier.uuidString,
//                     "deviceName": deviceName,
//                     "serviceUuid": "",
//                     "rssi": RSSI.intValue,
//                     "hasManufacturerData": false,
//                     "isPartialData": true // Flag to indicate this is incomplete
//                 ]
//                 scanResultsSink(result)
//             } else {
//                 for serviceUUID in serviceUUIDs {
//                     let result: [String: Any] = [
//                         "deviceId": peripheral.identifier.uuidString,
//                         "deviceName": deviceName,
//                         "serviceUuid": serviceUUID.uuidString,
//                         "rssi": RSSI.intValue,
//                         "extractedUuid": "", // Will be filled after connection
//                         "hasManufacturerData": false,
//                         "isPartialData": true
//                     ]
//                     scanResultsSink(result)
//                 }
//             }
//         }
//     }

//     // MARK: - Application Lifecycle

//     override func applicationDidEnterBackground(_ application: UIApplication) {
//         NSLog("App entered background")

//         let authStatus: CLAuthorizationStatus
//         if #available(iOS 14.0, *) {
//             authStatus = locationManager?.authorizationStatus ?? .notDetermined
//         } else {
//             authStatus = CLLocationManager.authorizationStatus()
//         }

//         if isAdvertisingInBackground || isScanningInBackground {
//             switch authStatus {
//             case .authorizedAlways:
//                 NSLog("Have always location permission - starting background tasks")
//                 beginBackgroundTask()
//                 scheduleBackgroundTasks()
//                 locationManager?.startUpdatingLocation()

//             case .authorizedWhenInUse:
//                 NSLog("Only have when-in-use permission - limited background time available")
//                 beginBackgroundTask()

//             case .denied, .restricted, .notDetermined:
//                 NSLog("No location permission - background time will be limited")
//                 beginBackgroundTask()

//             @unknown default:
//                 NSLog("Unknown location permission status")
//                 beginBackgroundTask()
//             }
//         }
//     }

//     private func checkBackgroundCapabilities() -> (canRunInBackground: Bool, reason: String) {
//         let authStatus: CLAuthorizationStatus
//         if #available(iOS 14.0, *) {
//             authStatus = locationManager?.authorizationStatus ?? .notDetermined
//         } else {
//             authStatus = CLLocationManager.authorizationStatus()
//         }

//         switch authStatus {
//         case .authorizedAlways:
//             return (true, "Full background access available")
//         case .authorizedWhenInUse:
//             return (false, "Limited background access - upgrade to 'Always' permission for full functionality")
//         case .denied, .restricted:
//             return (false, "No background access - location permission denied")
//         case .notDetermined:
//             return (false, "Location permission not requested")
//         @unknown default:
//             return (false, "Unknown permission status")
//         }
//     }

//     override func applicationWillEnterForeground(_ application: UIApplication) {
//         NSLog("App will enter foreground")
//         endBackgroundTask()
//     }

//     override func applicationWillTerminate(_ application: UIApplication) {
//         NSLog("App will terminate")
//         endBackgroundTask()
//     }

//     // MARK: - Event Sink

//     func setScanResultsSink(_ sink: FlutterEventSink?) {
//         self.scanResultsSink = sink
//     }
// }

// // Stream handler for scan results
// class ScanResultsStreamHandler: NSObject, FlutterStreamHandler {
//     private weak var appDelegate: AppDelegate?

//     init(appDelegate: AppDelegate) {
//         self.appDelegate = appDelegate
//         super.init()
//     }

//     func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
//         appDelegate?.setScanResultsSink(events)
//         return nil
//     }

//     func onCancel(withArguments arguments: Any?) -> FlutterError? {
//         appDelegate?.setScanResultsSink(nil)
//         return nil
//     }
// }
