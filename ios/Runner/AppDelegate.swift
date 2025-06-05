import CoreBluetooth
import CoreLocation
import Flutter
import UIKit

@UIApplicationMain
class AppDelegate: FlutterAppDelegate, CBPeripheralManagerDelegate, CBCentralManagerDelegate,
  CBPeripheralDelegate, CLLocationManagerDelegate
{

  private var methodChannel: FlutterMethodChannel?
  private var locationManager: CLLocationManager!
  private var peripheralManager: CBPeripheralManager?
  private var centralManager: CBCentralManager?

  // BLE Properties
  private var currentAdvertisingUUID: String = ""
  private var isAdvertising: Bool = false
  private var isScanning: Bool = false
  private var scannedDevices: [String: [String: Any]] = [:]

  // Background Properties
  private var backgroundTask: UIBackgroundTaskIdentifier = UIBackgroundTaskIdentifier.invalid
  private var backgroundThreadStarted = false
  private var shouldStopBackgroundTasks = false

  // Queues
  private let centralQueue = DispatchQueue.global(qos: .userInitiated)
  private let peripheralQueue = DispatchQueue.global(qos: .userInitiated)

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // Flutter setup
    let controller = window?.rootViewController as! FlutterViewController
    methodChannel = FlutterMethodChannel(
      name: "ble_advertiser_scanner",
      binaryMessenger: controller.binaryMessenger
    )

    setupMethodChannel()
    setupBluetooth()
    setupLocationServices()
    requestNotificationPermission()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - Method Channel Setup
  private func setupMethodChannel() {
    methodChannel?.setMethodCallHandler {
      [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard let self = self else { return }

      switch call.method {
      case "startAdvertising":
        self.handleStartAdvertising(call: call, result: result)
      case "stopAdvertising":
        self.handleStopAdvertising(result: result)
      case "startScanning":
        self.handleStartScanning(result: result)
      case "stopScanning":
        self.handleStopScanning(result: result)
      case "getScannedDevices":
        self.handleGetScannedDevices(result: result)
      case "clearScannedDevices":
        self.handleClearScannedDevices(result: result)
      case "isAdvertising":
        result(self.isAdvertising)
      case "isScanning":
        result(self.isScanning)
      case "enableBackgroundMode":
        self.handleEnableBackgroundMode(result: result)
      case "disableBackgroundMode":
        self.handleDisableBackgroundMode(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - Method Channel Handlers
  private func handleStartAdvertising(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
      let uuid = args["uuid"] as? String
    else {
      result(FlutterError(code: "INVALID_ARGUMENTS", message: "UUID is required", details: nil))
      return
    }

    currentAdvertisingUUID = uuid
    // startAdvertising(uuid: uuid)
    startAdvertisingWithManufacturerData(uuid: uuid)
    result(true)
  }

  private func handleStopAdvertising(result: @escaping FlutterResult) {
    stopAdvertising()
    result(true)
  }

  private func handleStartScanning(result: @escaping FlutterResult) {
    startScanning()
    result(true)
  }

  private func handleStopScanning(result: @escaping FlutterResult) {
    stopScanning()
    result(true)
  }

  private func handleGetScannedDevices(result: @escaping FlutterResult) {
    let devicesList = Array(scannedDevices.values)
    result(devicesList)
  }

  private func handleClearScannedDevices(result: @escaping FlutterResult) {
    scannedDevices.removeAll()
    result(true)
  }

  private func handleEnableBackgroundMode(result: @escaping FlutterResult) {
    enableBackgroundMode()
    result(true)
  }

  private func handleDisableBackgroundMode(result: @escaping FlutterResult) {
    disableBackgroundMode()
    result(true)
  }

  // MARK: - Bluetooth Setup
  private func setupBluetooth() {
    centralManager = CBCentralManager(delegate: self, queue: centralQueue)
    peripheralManager = CBPeripheralManager(delegate: self, queue: peripheralQueue)
  }

  // MARK: - Location Services Setup
  private func setupLocationServices() {
    locationManager = CLLocationManager()
    locationManager.delegate = self
    locationManager.requestAlwaysAuthorization()
    locationManager.pausesLocationUpdatesAutomatically = false
    locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    locationManager.distanceFilter = 3000.0

    if #available(iOS 9.0, *) {
      locationManager.allowsBackgroundLocationUpdates = true
    }
  }

  private func requestNotificationPermission() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) {
      granted, error in
      if let error = error {
        NSLog("Notification permission error: \(error)")
      }
    }
  }

  // MARK: - BLE Advertising
  // private func startAdvertising(uuid: String) {
  //   guard let peripheralManager = peripheralManager,
  //     peripheralManager.state == .poweredOn
  //   else {
  //     NSLog("Peripheral manager not ready")
  //     return
  //   }

  //   peripheralManager.stopAdvertising()

  //   let serviceUUID = CBUUID(string: uuid)
  //   let advertisementData =
  //     [
  //       CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
  //       CBAdvertisementDataLocalNameKey: "FlutterBLE",
  //     ] as [String: Any]

  //   peripheralManager.startAdvertising(advertisementData)
  //   isAdvertising = true

  //   NSLog("Started advertising UUID: \(uuid)")
  //   notifyFlutter(method: "onAdvertisingStarted", arguments: ["uuid": uuid])
  // }

  private func startAdvertisingWithManufacturerData(uuid: String) {
    guard let peripheralManager = peripheralManager,
      peripheralManager.state == .poweredOn
    else {
      NSLog("Peripheral manager not ready")
      return
    }

    peripheralManager.stopAdvertising()

    let serviceUUID = CBUUID(string: uuid)

    // Convert UUID to manufacturer data
    let uuidData = uuid.data(using: .utf8) ?? Data()
    let manufacturerData = Data([0xFF, 0xFF]) + uuidData  // Using 0xFFFF as company identifier

    let advertisementData: [String: Any] = [
      CBAdvertisementDataLocalNameKey: "FlutterBLE",
      CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
      CBAdvertisementDataManufacturerDataKey: manufacturerData,
    ]

    peripheralManager.startAdvertising(advertisementData)
    isAdvertising = true

    NSLog("Started advertising with manufacturer data - UUID: \(uuid)")
    notifyFlutter(method: "onAdvertisingStarted", arguments: ["uuid": uuid])
  }

  private func stopAdvertising() {
    peripheralManager?.stopAdvertising()
    isAdvertising = false
    currentAdvertisingUUID = ""

    NSLog("Stopped advertising")
    notifyFlutter(method: "onAdvertisingStopped", arguments: nil)
  }

  // MARK: - BLE Scanning
  private func startScanning() {
    guard let centralManager = centralManager,
      centralManager.state == .poweredOn
    else {
      NSLog("Central manager not ready")
      return
    }

    centralManager.stopScan()

    // Scan for all services to detect any advertising devices
    centralManager.scanForPeripherals(
      withServices: nil,
      options: [
        CBCentralManagerScanOptionAllowDuplicatesKey: true
      ])

    isScanning = true
    NSLog("Started scanning for devices")
    notifyFlutter(method: "onScanningStarted", arguments: nil)

    // Auto-restart scanning every 30 seconds to maintain detection
    DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) { [weak self] in
      if self?.isScanning == true {
        self?.restartScanning()
      }
    }
  }

  private func stopScanning() {
    centralManager?.stopScan()
    isScanning = false

    NSLog("Stopped scanning")
    notifyFlutter(method: "onScanningStopped", arguments: nil)
  }

  private func restartScanning() {
    centralManager?.stopScan()

    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      self?.startScanning()
    }
  }

  // MARK: - Background Mode
  private func enableBackgroundMode() {
    // Start location updates to maintain background execution
    locationManager.startUpdatingLocation()

    // Start beacon ranging for additional background time
    let beaconRegion = CLBeaconRegion(
      proximityUUID: UUID(uuidString: "2F234454-CF6D-4A0F-ADF2-F4911BA9FFA6")!,
      identifier: "background-beacon-region"
    )
    locationManager.startRangingBeacons(in: beaconRegion)

    // Start background task
    startBackgroundTask()

    NSLog("Background mode enabled")
    notifyFlutter(method: "onBackgroundModeEnabled", arguments: nil)
  }

  private func disableBackgroundMode() {
    locationManager.stopUpdatingLocation()
    locationManager.stopRangingBeacons(
      in: CLBeaconRegion(
        proximityUUID: UUID(uuidString: "2F234454-CF6D-4A0F-ADF2-F4911BA9FFA6")!,
        identifier: "background-beacon-region"
      ))

    stopBackgroundTask()

    NSLog("Background mode disabled")
    notifyFlutter(method: "onBackgroundModeDisabled", arguments: nil)
  }

  private func startBackgroundTask() {
    guard !backgroundThreadStarted else { return }

    backgroundThreadStarted = true
    shouldStopBackgroundTasks = false

    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "BLEBackgroundTask") {
      [weak self] in
      NSLog("Background task expired")
      self?.stopBackgroundTask()
    }

    DispatchQueue.global().async { [weak self] in
      self?.backgroundTaskLoop()
    }
  }

  private func stopBackgroundTask() {
    shouldStopBackgroundTasks = true

    if backgroundTask != .invalid {
      UIApplication.shared.endBackgroundTask(backgroundTask)
      backgroundTask = .invalid
    }

    backgroundThreadStarted = false
  }

  private func backgroundTaskLoop() {
    var lastLogTime = Date().timeIntervalSince1970

    while !shouldStopBackgroundTasks {
      DispatchQueue.main.async { [weak self] in
        let now = Date().timeIntervalSince1970
        let backgroundTimeRemaining = UIApplication.shared.backgroundTimeRemaining

        // Log background time remaining every 10 seconds
        if now - lastLogTime >= 10.0 {
          lastLogTime = now
          NSLog("Background time remaining: \(backgroundTimeRemaining)")

          if backgroundTimeRemaining < 30.0 {
            NSLog("Background time running low!")
          }
        }

        // Maintain BLE operations in background
        let appState = UIApplication.shared.applicationState
        if appState == .background {
          // Restart scanning if it was running
          if self?.isScanning == true && self?.centralManager?.isScanning == false {
            self?.startScanning()
          }

          // Restart advertising if it was running
          if self?.isAdvertising == true && self?.peripheralManager?.isAdvertising == false {
            if !self!.currentAdvertisingUUID.isEmpty {
              // self?.startAdvertising(uuid: self!.currentAdvertisingUUID)
              self?.startAdvertisingWithManufacturerData(uuid: self!.currentAdvertisingUUID)
            }
          }
        }
      }

      sleep(1)
    }

    NSLog("Background task loop ended")
  }

  // MARK: - Flutter Communication
  private func notifyFlutter(method: String, arguments: Any?) {
    DispatchQueue.main.async { [weak self] in
      self?.methodChannel?.invokeMethod(method, arguments: arguments)
    }
  }

  // MARK: - CBCentralManagerDelegate
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    let stateString: String
    switch central.state {
    case .poweredOn:
      stateString = "poweredOn"
    case .poweredOff:
      stateString = "poweredOff"
    case .unsupported:
      stateString = "unsupported"
    case .unauthorized:
      stateString = "unauthorized"
    case .resetting:
      stateString = "resetting"
    default:
      stateString = "unknown"
    }

    NSLog("Central manager state: \(stateString)")
    notifyFlutter(method: "onBluetoothStateChanged", arguments: ["state": stateString])
  }

  func centralManager(
    _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any], rssi RSSI: NSNumber
  ) {

    let deviceId = peripheral.identifier.uuidString
    let name =
      peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown"
    let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
    let serviceUUIDStrings = serviceUUIDs.map { $0.uuidString }

    // let deviceInfo: [String: Any] = [
    //   "id": deviceId,
    //   "name": name,
    //   "rssi": RSSI.intValue,
    //   "serviceUUIDs": serviceUUIDStrings,
    //   "timestamp": Date().timeIntervalSince1970,
    // ]

    // // Update or add device to scanned devices
    // scannedDevices[deviceId] = deviceInfo

    // NSLog("Discovered device: \(name), RSSI: \(RSSI), UUIDs: \(serviceUUIDStrings)")

    // // Notify Flutter
    // notifyFlutter(method: "onDeviceDiscovered", arguments: deviceInfo)

    // Extract UUID from manufacturer data
    var extractedUUID: String? = nil
    if let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
      manufacturerData.count > 2
    {
      let uuidData = manufacturerData.dropFirst(2)  // Remove company identifier
      extractedUUID = String(data: uuidData, encoding: .utf8)
    }

    let deviceInfo: [String: Any] = [
      "id": deviceId,
      "name": name,
      "rssi": RSSI.intValue,
      "serviceUUIDs": serviceUUIDStrings,
      "extractedUUID": extractedUUID ?? "",
      "timestamp": Date().timeIntervalSince1970,
      "hasManufacturerData": advertisementData[CBAdvertisementDataManufacturerDataKey] != nil,
    ]

    // Update or add device to scanned devices
    scannedDevices[deviceId] = deviceInfo

    NSLog("Discovered device: \(name), RSSI: \(RSSI)")
    NSLog("Service UUIDs: \(serviceUUIDStrings)")
    NSLog("Extracted UUID: \(extractedUUID ?? "none")")

    // Notify Flutter
    notifyFlutter(method: "onDeviceDiscovered", arguments: deviceInfo)
  }

  // MARK: - CBPeripheralManagerDelegate
  func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    let stateString: String
    switch peripheral.state {
    case .poweredOn:
      stateString = "poweredOn"
    case .poweredOff:
      stateString = "poweredOff"
    case .unsupported:
      stateString = "unsupported"
    case .unauthorized:
      stateString = "unauthorized"
    case .resetting:
      stateString = "resetting"
    default:
      stateString = "unknown"
    }

    NSLog("Peripheral manager state: \(stateString)")
    notifyFlutter(method: "onPeripheralStateChanged", arguments: ["state": stateString])
  }

  func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
    if let error = error {
      NSLog("Advertising failed: \(error.localizedDescription)")
      notifyFlutter(method: "onAdvertisingError", arguments: ["error": error.localizedDescription])
      isAdvertising = false
    } else {
      NSLog("Advertising started successfully")
    }
  }

  // MARK: - CLLocationManagerDelegate
  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    // We don't need to do anything with location updates
    // This is just to maintain background execution
  }

  func locationManager(
    _ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus
  ) {
    let statusString: String
    switch status {
    case .authorizedAlways:
      statusString = "authorizedAlways"
    case .authorizedWhenInUse:
      statusString = "authorizedWhenInUse"
    case .denied:
      statusString = "denied"
    case .restricted:
      statusString = "restricted"
    case .notDetermined:
      statusString = "notDetermined"
    @unknown default:
      statusString = "unknown"
    }

    NSLog("Location authorization status: \(statusString)")
    notifyFlutter(method: "onLocationAuthorizationChanged", arguments: ["status": statusString])
  }

  func locationManager(
    _ manager: CLLocationManager, didRangeBeacons beacons: [CLBeacon], in region: CLBeaconRegion
  ) {
    // This is for background execution maintenance
  }
}
