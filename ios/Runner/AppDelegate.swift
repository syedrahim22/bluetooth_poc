import CoreBluetooth
import CoreLocation
import Flutter
import FirebaseCore
import UIKit
import FirebaseMessaging

@UIApplicationMain
class AppDelegate: FlutterAppDelegate, CBPeripheralManagerDelegate, CBCentralManagerDelegate,
  CBPeripheralDelegate, CLLocationManagerDelegate, MessagingDelegate
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
    FirebaseApp.configure()
    Messaging.messaging().delegate = self
    GeneratedPluginRegistrant.register(with: self)
    let controller = window?.rootViewController as! FlutterViewController
    methodChannel = FlutterMethodChannel(
      name: "ble_advertiser_scanner",
      binaryMessenger: controller.binaryMessenger
    )

    setupMethodChannel()
    setupBluetooth()
    setupLocationServices()
    requestNotificationPermission()

    application.registerForRemoteNotifications()

    if let uuid = UserDefaults.standard.string(forKey: "ble_uuid") {
      NSLog("App launched, resuming advertising with UUID: \(uuid)")
      startAdvertisingWithManufacturerData(uuid: uuid)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func startAdvertisingFromBackground(uuid: String) {
      guard let peripheralManager = peripheralManager,
            peripheralManager.state == .poweredOn
      else {
          NSLog("Peripheral manager not ready for background advertising.")
          return
      }

      peripheralManager.stopAdvertising()

      let serviceUUID = CBUUID(string: uuid)

      let advertisementData: [String: Any] = [
          CBAdvertisementDataServiceUUIDsKey: [serviceUUID]
      ]

      peripheralManager.startAdvertising(advertisementData)
      isAdvertising = true

      NSLog("Started advertising from background with service UUID: \(uuid)")
      notifyFlutter(method: "onAdvertisingStarted", arguments: ["uuid": uuid])
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
      case "startAdvertisingFromStoredUUID":
        if let uuid = UserDefaults.standard.string(forKey: "ble_uuid") {
            NSLog("Silent push triggered: Starting advertising from stored UUID: \(uuid)")
            self.currentAdvertisingUUID = uuid
            self.startAdvertisingFromBackground(uuid: uuid)
            result(true)
        } else {
            NSLog("Silent push triggered but no UUID found in UserDefaults")
            result(FlutterError(code: "NO_UUID", message: "No UUID found in UserDefaults", details: nil))
        }
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
      let uuid = args["uuid"] as? String else {
      result(FlutterError(code: "INVALID_ARGUMENTS", message: "UUID is required", details: nil))
      return
    }

    currentAdvertisingUUID = uuid
    UserDefaults.standard.set(uuid, forKey: "ble_uuid")
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

    func locationManager(
      _ manager: CLLocationManager,
      didRangeBeacons beacons: [CLBeacon],
      in region: CLBeaconRegion
    ) {
    NSLog("here");
      for beacon in beacons {
        let beaconInfo: [String: Any] = [
          "uuid": beacon.proximityUUID.uuidString,
          "major": beacon.major,
          "minor": beacon.minor,
          "rssi": beacon.rssi,
          "accuracy": beacon.accuracy,
          "proximity": beacon.proximity.rawValue,
          "timestamp": Date().timeIntervalSince1970
        ]

        NSLog("onBeaconDetected should fire now: \(beaconInfo)")
        notifyFlutter(method: "onBeaconDetected", arguments: beaconInfo)
      }
    }

  // MARK: - UNUserNotificationCenterDelegate
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.alert, .sound, .badge])
  }

  // MARK: - UIApplicationDelegate for APNS
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    // Forward APNS token to Firebase Messaging
    Messaging.messaging().apnsToken = deviceToken
    NSLog("Registered for remote notifications with APNS token: \(deviceToken.map { String(format: "%02hhx", $0) }.joined())")
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog("Failed to register for remote notifications: \(error.localizedDescription)")
  }

  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    NSLog("FCM Token: \(fcmToken ?? "null")")
  }

  private func requestNotificationPermission() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) {
      granted, error in
      if let error = error {
        NSLog("Notification permission error: \(error)")
      }

      DispatchQueue.main.async {
        UIApplication.shared.registerForRemoteNotifications()
      }
    }
  }

  private func startAdvertisingWithManufacturerData(uuid: String) {
    guard let peripheralManager = peripheralManager,
      peripheralManager.state == .poweredOn
    else {
      NSLog("Peripheral manager not ready. State: \(String(describing: peripheralManager?.state.rawValue))")
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
  _ central: CBCentralManager,
  didDiscover peripheral: CBPeripheral,
  advertisementData: [String: Any],
  rssi RSSI: NSNumber
) {
  let deviceId = peripheral.identifier.uuidString
  let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown"
  let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
  let serviceUUIDStrings = serviceUUIDs.map { $0.uuidString }

  var manufacturerHex: String = ""
  var extractedUUID: String? = nil
  var beaconType: String? = nil

  if let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
    manufacturerHex = manufacturerData.map { String(format: "%02x", $0) }.joined()
    NSLog("Manufacturer data hex: \(manufacturerHex)")

    // Try basic UUID extraction (fallback)
    if manufacturerData.count > 2 {
      let uuidData = manufacturerData.dropFirst(2)
      extractedUUID = String(data: uuidData, encoding: .utf8)
    }

    // Check for iBeacon (Apple)
    if manufacturerData.count >= 25,
       manufacturerData[0] == 0x4C, manufacturerData[1] == 0x00,
       manufacturerData[2] == 0x02, manufacturerData[3] == 0x15 {
      beaconType = "iBeacon"

      let uuidBytes = manufacturerData.subdata(in: 4..<20)
      let uuid = NSUUID(uuidBytes: [UInt8](uuidBytes)) as UUID
      let major = manufacturerData.subdata(in: 20..<22).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
      let minor = manufacturerData.subdata(in: 22..<24).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
      let txPower = Int8(bitPattern: manufacturerData[24])

      let beaconInfo: [String: Any] = [
        "format": beaconType ?? "unknown",
        "uuid": uuid.uuidString,
        "major": major,
        "minor": minor,
        "rssi": RSSI.intValue,
        "txPower": txPower,
        "timestamp": Date().timeIntervalSince1970
      ]

      NSLog("onBeaconDetected should fire now: \(beaconInfo)")
      notifyFlutter(method: "onBeaconDetected", arguments: beaconInfo)
    }

    // Check for Eddystone (Google)
    else if manufacturerData.count >= 3,
            manufacturerData[0] == 0xAA, manufacturerData[1] == 0xFE {
      beaconType = "Eddystone"

      // Minimal Eddystone beacon parsing
      let frameType = manufacturerData[2]
      var beaconData: [String: Any] = [
        "format": beaconType!,
        "frameType": frameType,
        "rssi": RSSI.intValue,
        "manufacturerHex": manufacturerHex,
        "timestamp": Date().timeIntervalSince1970
      ]

      // Optionally parse more Eddystone fields (UID, URL, etc.)
      NSLog("onBeaconDetected should fire now: \(beaconData)")
      notifyFlutter(method: "onBeaconDetected", arguments: beaconData)
    }

    // Add more custom beacon formats here if needed
  }

  // Notify Flutter of any BLE device (beacon or not)
  let deviceInfo: [String: Any] = [
    "id": deviceId,
    "name": name,
    "rssi": RSSI.intValue,
    "serviceUUIDs": serviceUUIDStrings,
    "extractedUUID": extractedUUID ?? "",
    "manufacturerHex": manufacturerHex,
    "isBeacon": beaconType != nil,
    "beaconType": beaconType ?? "none",
    "timestamp": Date().timeIntervalSince1970
  ]

  scannedDevices[deviceId] = deviceInfo
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
}
