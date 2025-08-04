import 'dart:developer';
import 'dart:io';

import 'package:bluetooth_poc/controller/requirement_state_controller.dart';
import 'package:bluetooth_poc/models/device_request.dart';
import 'package:bluetooth_poc/models/personnel_response.dart';
import 'package:bluetooth_poc/service/device_service.dart';
import 'package:dchs_flutter_beacon/dchs_flutter_beacon.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:collection/collection.dart';
import 'package:get/get.dart';
import 'dart:async';


class BLEHomePage extends StatefulWidget {
  const BLEHomePage({super.key});

  @override
  BLEHomePageState createState() => BLEHomePageState();
}

class BLEHomePageState extends State<BLEHomePage> with WidgetsBindingObserver {
  static const platform = MethodChannel('ble_advertiser_scanner');

  // State variables
  StreamSubscription<RangingResult>? _streamRanging;
  final _regionBeacons = <Region, List<Beacon>>{};
  final _beacons = <Beacon>[];
  final controller = Get.find<RequirementStateController>();
  final Set<int> _expandedIndexes = {};

  List<Map<String, dynamic>> _scannedDevices = [];
  StreamSubscription<BluetoothState>? _streamBluetooth;
  Timer? _sendToBackendTimer;
  bool isDataLoading = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.delayed(Duration(seconds: 0), () async {
      await checkAllRequirements();
    });
    listeningState();
    _setupMethodChannelHandler();
    _checkInitialStates();
    controller.startStream.listen((flag) {
      if (flag == true) {
        initScanBeacon();
        _startScanning();
        _sendToBackendTimer?.cancel();
        _sendToBackendTimer = Timer.periodic(Duration(seconds: 5), (_) {
          if (controller.deviceList.isNotEmpty) {
            setState(() {
              isDataLoading = true;
            });
            lookupPersonnelDevices(controller.deviceList).then((response) {
              if (response != null) {
                controller.addPersonnelDetails(response.data.personnel);
              }
              setState(() {
                isDataLoading = false;
              });
            });
          }
        });
      }
    });
    controller.pauseStream.listen((flag) {
      if (flag == true) {
        pauseScanBeacon();
        _stopScanning();
        _sendToBackendTimer?.cancel();
      }
    });
  }

  DeviceInfo _beaconToDeviceInfo(Beacon b) {
    return DeviceInfo(
      type: 'Bluetooth tag',
      address: b.proximityUUID,
      major: b.major,
      minor: b.minor,
    );
  }

  initScanBeacon() async {
    await flutterBeacon.setScanPeriod(1000);
    await flutterBeacon.setBetweenScanPeriod(500);
    if (Platform.isAndroid) {
      await flutterBeacon.setUseTrackingCache(true);
      await flutterBeacon.setMaxTrackingAge(10000);
      await flutterBeacon.setBackgroundScanPeriod(1000);
      await flutterBeacon.setBackgroundBetweenScanPeriod(500);
    }

    await flutterBeacon.initializeScanning;
    if (!controller.authorizationStatusOk ||
        !controller.locationServiceEnabled ||
        !controller.bluetoothEnabled) {
      if (kDebugMode) {
        print(
            'RETURNED, authorizationStatusOk=${controller.authorizationStatusOk}, '
            'locationServiceEnabled=${controller.locationServiceEnabled}, '
            'bluetoothEnabled=${controller.bluetoothEnabled}');
      }
      return;
    }
    var regions = <Region>[];
    if (Platform.isIOS) {
      regions = <Region>[
        Region(
          identifier: 'Cubeacon',
          proximityUUID: 'D68FA139-7E78-4F74-8666-278CB024281F',
        ),
      ];
    } else {
      regions = [
        Region(
          identifier: 'all-beacons',
        ),
      ];
    }

    if (_streamRanging != null) {
      if (_streamRanging!.isPaused) {
        _streamRanging?.resume();
        return;
      }
    }

    _streamRanging =
        flutterBeacon.ranging(regions).listen((RangingResult result) {
      if (kDebugMode) {
        print(result);
      }
      if (mounted) {
        setState(() {
          _regionBeacons[result.region] = result.beacons;
          _beacons.clear();
          controller.clearDevices();
          for (var list in _regionBeacons.values) {
            _beacons.addAll(list);
          }
          for (var beacon in _beacons) {
            controller.addDevice(_beaconToDeviceInfo(beacon));
          }
          _beacons.sort(_compareParameters);
        });
      }
    });
  }

  pauseScanBeacon() async {
    _streamRanging?.pause();
  }

  int _compareParameters(Beacon a, Beacon b) {
    int compare = a.proximityUUID.compareTo(b.proximityUUID);

    if (compare == 0) {
      compare = a.major.compareTo(b.major);
    }

    if (compare == 0) {
      compare = a.minor.compareTo(b.minor);
    }

    return compare;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _streamRanging?.cancel();
    _streamBluetooth?.cancel();
    _sendToBackendTimer?.cancel();
    super.dispose();
  }

  listeningState() async {
    if (kDebugMode) {
      print('Listening to bluetooth state');
    }
    _streamBluetooth = flutterBeacon
        .bluetoothStateChanged()
        .listen((BluetoothState state) async {
      controller.updateBluetoothState(state);
      await checkAllRequirements();
    });
  }

  checkAllRequirements() async {
    final bluetoothState = await flutterBeacon.bluetoothState;
    controller.updateBluetoothState(bluetoothState);
    if (kDebugMode) {
      print('BLUETOOTH $bluetoothState');
    }

    final authorizationStatus = await flutterBeacon.authorizationStatus;
    controller.updateAuthorizationStatus(authorizationStatus);
    if (kDebugMode) {
      print('AUTHORIZATION $authorizationStatus');
    }

    final locationServiceEnabled =
        await flutterBeacon.checkLocationServicesIfEnabled;
    controller.updateLocationService(locationServiceEnabled);
    if (kDebugMode) {
      print('LOCATION SERVICE $locationServiceEnabled');
    }

    if (controller.bluetoothEnabled &&
        controller.authorizationStatusOk &&
        controller.locationServiceEnabled) {
      if (kDebugMode) {
        print('STATE READY');
      }
      if (kDebugMode) {
        print('SCANNING');
      }
    } else {
      if (kDebugMode) {
        print('STATE NOT READY');
      }
      controller.pauseScanningFunc();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);
    if (kDebugMode) {
      print('AppLifecycleState = $state');
    }
    if (state == AppLifecycleState.resumed) {
      if (_streamBluetooth != null) {
        if (_streamBluetooth!.isPaused) {
          _streamBluetooth?.resume();
        }
      }
      await checkAllRequirements();
    } else if (state == AppLifecycleState.paused) {
      _streamBluetooth?.pause();
    }
  }

  void _setupMethodChannelHandler() {
    platform.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onDeviceDiscovered':
          _handleDeviceDiscovered(call.arguments);
          break;
      }
    });
  }

  void _handleDeviceDiscovered(dynamic arguments) {
    final deviceInfo = Map<String, dynamic>.from(arguments);
    final serviceUUIDs = List<String>.from(deviceInfo['serviceUUIDs'] ?? []);
    if (kDebugMode) {
      print(deviceInfo.toString());
    }

    if (serviceUUIDs.isEmpty) {
      return; // Skip devices that are neither BLE nor beacons
    }
    // BLE device logic
    final existingIndex =
        _scannedDevices.indexWhere((d) => d['id'] == deviceInfo['id']);

    if (existingIndex != -1) {
      final existingDevice = _scannedDevices[existingIndex];

      final isSame = existingDevice['rssi'] == deviceInfo['rssi'] &&
          existingDevice['name'] == deviceInfo['name'] &&
          ListEquality().equals(existingDevice['serviceUUIDs'], serviceUUIDs);

      if (isSame) return;

      setState(() {
        _scannedDevices[existingIndex] = deviceInfo;
      });
    } else {
      setState(() {
        _scannedDevices.insert(0, deviceInfo);
        if (_scannedDevices.length > 50) {
          _scannedDevices = _scannedDevices.take(50).toList();
        }
      });
    }
    if (deviceInfo['isBeacon'] == false) {
      final serviceUUIDs = List<String>.from(deviceInfo['serviceUUIDs'] ?? []);

      if (serviceUUIDs.isNotEmpty) {
        final address = serviceUUIDs.first;

        controller.addDevice(DeviceInfo(
          type: 'Mobile',
          address: address,
        ));
      }
    }
  }

  void _addLog(String message) {
    debugPrint(message);
  }

  Future<void> _checkInitialStates() async {
    try {
      final devices = await platform.invokeMethod('getScannedDevices');
      if (devices != null) {
        _scannedDevices = List<Map<String, dynamic>>.from(
            devices.map((device) => Map<String, dynamic>.from(device)));
      }

      setState(() {});
      _addLog('Initial states loaded');
    } catch (e) {
      _addLog('Error loading initial states: $e');
    }
  }

  Future<void> _startScanning() async {
    try {
      await platform.invokeMethod('startScanning');
      _addLog('Start scanning requested');
    } catch (e) {
      _addLog('Error starting scanning: $e');
      _showSnackBar('Failed to start scanning: $e');
    }
  }

  Future<void> _stopScanning() async {
    try {
      await platform.invokeMethod('stopScanning');
      _addLog('Stop scanning requested');
    } catch (e) {
      _addLog('Error stopping scanning: $e');
      _showSnackBar('Failed to stop scanning: $e');
    }
  }

  void _showSnackBar(String message) {
    log(message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('BLE Advertiser Scanner'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Status Bar

          // Main Content
          Expanded(
            child: _buildScanTab(),
          ),
        ],
      ),
    );
  }

  Widget _buildScanTab() {
    return Column(
      children: [
        // Scan Controls
        Container(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    if (!controller.bluetoothEnabled ||
                        !controller.authorizationStatusOk ||
                        !controller.locationServiceEnabled) {
                    } else {
                      controller.startScanningFunc();
                    }
                  },
                  icon: Icon(Icons.search),
                  label: Text('Start Scanning'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    if (controller.startScanning.value) {
                      controller.pauseScanningFunc();
                    }
                  },
                  icon: Icon(Icons.stop),
                  label: Text('Stop Scanning'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Device List
        Obx(() => !controller.bluetoothEnabled
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Bluetooth Permission Not Granted',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Please enable Bluetooth use for this app from Settings',
                      style: TextStyle(fontWeight: FontWeight.normal),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            : (!controller.locationServiceEnabled ||
                    !controller.authorizationStatusOk)
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Location Permission Not Granted',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Please enable Location use for this app from Settings',
                          style: TextStyle(fontWeight: FontWeight.normal),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : Expanded(
                    child: Column(
                      children: [
                        Expanded(
                            child: controller.personnelDetails.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.bluetooth_searching,
                                            size: 64, color: Colors.grey),
                                        SizedBox(height: 16),
                                        Text(
                                          controller.startScanning.value ||
                                                  isDataLoading
                                              ? 'Scanning for devices...'
                                              : 'No devices found',
                                          style: TextStyle(
                                              fontSize: 16, color: Colors.grey),
                                        ),
                                        if (controller.pauseScanning.value)
                                          Text(
                                            'Start scanning to discover BLE devices',
                                            style: TextStyle(
                                                fontSize: 14,
                                                color: Colors.grey[600]),
                                          ),
                                      ],
                                    ),
                                  )
                                : buildPersonnelCards(
                                    controller.personnelDetails)),
                      ],
                    ),
                  )),
      ],
    );
  }

  Widget buildPersonnelCards(List<Personnel> personnelList) {
    return ListView.builder(
      itemCount: personnelList.length,
      itemBuilder: (context, index) {
        final person = personnelList[index];
        final isExpanded = _expandedIndexes.contains(index);
        return GestureDetector(
           onTap: () {
            setState(() {
              if (isExpanded) {
                _expandedIndexes.remove(index);
              } else {
                _expandedIndexes.add(index);
              }
            });
          },
          child: Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Person name
                  Text(
                    '${person.firstName} ${person.lastName}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Devices for this person
                  if (isExpanded) ...[
                  ...person.devices
                      .map((device) => _buildPersonDeviceCard(device))
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPersonDeviceCard(Device device) {
    final title = '${device.deviceName} (${device.type})';
    final hasUUID = device.address != null && device.address!.isNotEmpty;
    final hasMajorMinor = device.major != null && device.minor != null;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          if (hasUUID)
            Text(
              'UUID: ${device.address}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[700],
                fontFamily: 'monospace',
              ),
            ),
          if (hasMajorMinor)
            Text(
              'Major: ${device.major}, Minor: ${device.minor}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[700],
              ),
            ),
        ],
      ),
    );
  }
}
