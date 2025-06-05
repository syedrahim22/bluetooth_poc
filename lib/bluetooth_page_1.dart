import 'dart:async';
import 'dart:developer';
import 'dart:io';
// import 'package:bluetooth_info/bluetooth_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dart:math' as math;

import 'package:permission_handler/permission_handler.dart';

class BleAdvertiser {
  static const MethodChannel _channel = MethodChannel('ble_advertiser');
  static const EventChannel _scanResultsChannel =
      EventChannel('ble_advertiser_scan_results');

  static Stream<Map<String, dynamic>>? _scanResultsStream;

  /// Generate a unique UUID for this device
  static String generateUniqueUuid() {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replaceAllMapped(
      RegExp(r'[xy]'),
      (match) {
        var r = (DateTime.now().millisecondsSinceEpoch +
                math.Random().nextInt(16)) %
            16;
        var v = match.group(0) == 'x' ? r : (r & 0x3 | 0x8);
        return v.toRadixString(16);
      },
    );
  }

  // static Future<String> getDeviceAddress() async {
  // String deviceAddress = await BluetoothInfo.getDeviceAddress();
  // print('Device Address: $deviceAddress');

  // return deviceAddress;
  // }

  /// Start advertising with the given service UUID
  /// Set [inBackground] to true to continue advertising when app is in background
  static Future<bool> startAdvertising({
    required String serviceUuid,
    bool inBackground = false,
  }) async {
    try {
      return await _channel.invokeMethod('startAdvertising', {
        'serviceUuid': serviceUuid,
        'inBackground': inBackground,
      });
    } catch (e) {
      print('Error starting advertising: $e');
      return false;
    }
  }

  /// Stop advertising
  static Future<bool> stopAdvertising() async {
    try {
      return await _channel.invokeMethod('stopAdvertising');
    } catch (e) {
      print('Error stopping advertising: $e');
      return false;
    }
  }

  /// Start scanning for BLE advertisements
  /// Set [inBackground] to true to continue scanning when app is in background
  static Future<bool> startScanning({bool inBackground = false}) async {
    try {
      return await _channel.invokeMethod('startScanning', {
        'inBackground': inBackground,
      });
    } catch (e) {
      print('Error starting scanning: $e');
      return false;
    }
  }

  /// Stop scanning
  static Future<bool> stopScanning() async {
    try {
      return await _channel.invokeMethod('stopScanning');
    } catch (e) {
      print('Error stopping scanning: $e');
      return false;
    }
  }

  /// Check if Bluetooth is enabled
  static Future<bool> isBluetoothEnabled() async {
    try {
      return await _channel.invokeMethod('isBluetoothEnabled');
    } catch (e) {
      print('Error checking Bluetooth state: $e');
      return false;
    }
  }

  /// Request "Always" location permission (required for iOS background operation)
  static Future<bool> requestAlwaysLocationPermission() async {
    if (Platform.isIOS) {
      try {
        return await _channel.invokeMethod('requestAlwaysLocationPermission');
      } catch (e) {
        print('Error requesting always location permission: $e');
        return false;
      }
    }
    return true; // Not needed on other platforms
  }

  // Method to check background status
  static Future<Map<String, dynamic>> getBackgroundStatus() async {
    try {
      final result = await _channel.invokeMethod('getBackgroundStatus');
      return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      print("Error getting background status: ${e.message}");
      return {
        'canRunInBackground': false,
        'reason': 'Error: ${e.message}',
        'hasLocationPermission': false,
        'backgroundTimeRemaining': 0.0
      };
    }
  }

  /// Get a stream of scan results
  static Stream<Map<String, dynamic>> get scanResults {
    _scanResultsStream ??= _scanResultsChannel
        .receiveBroadcastStream()
        .map((dynamic event) => Map<String, dynamic>.from(event));
    return _scanResultsStream!;
  }
}

class BleAdvertiseApp extends StatefulWidget {
  @override
  _BleAdvertiseAppState createState() => _BleAdvertiseAppState();
}

class _BleAdvertiseAppState extends State<BleAdvertiseApp>
    with WidgetsBindingObserver {
  String _deviceUuid = '';
  bool _isAdvertising = false;
  bool _isScanning = false;
  bool _backgroundModeEnabled = false;
  List<Map<String, dynamic>> _discoveredDevices = [];
  StreamSubscription? _scanSubscription;
  bool _permissionsGranted = false;

  Future<void> requestPermissions() async {
    // Request location permissions (required for Bluetooth scanning)
    if (Platform.isAndroid) {
      final Map<Permission, PermissionStatus> statuses = await <Permission>[
        Permission.location,
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
      ].request();

      if (await Permission.bluetoothScan.isGranted) {
        setState(() {
          _permissionsGranted = true;
        });
      } else {
        await Permission.bluetoothScan.request();
      }

      log('Android permission statuses: $statuses');
    } else if (Platform.isIOS) {
      // iOS needs bluetooth and location permissions for background operation
      final Map<Permission, PermissionStatus> statuses = await <Permission>[
        Permission.bluetooth,
        Permission.location,
      ].request();

      // Request "Always" location permission via native code
      bool alwaysGranted =
          await BleAdvertiser.requestAlwaysLocationPermission();

      setState(() {
        _permissionsGranted = alwaysGranted;
      });

      log('iOS permission statuses: $statuses, Always Location: $alwaysGranted');
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    requestPermissions();
    // Generate a unique ID for this device
    _deviceUuid = BleAdvertiser.generateUniqueUuid();
  }

  // Future<void> updateDeviceId() async {
  // _deviceUuid = await BleAdvertiser.getDeviceAddress();
  // }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle app lifecycle changes
    if (state == AppLifecycleState.resumed) {
      // App came back to foreground
      _checkOperationStatus();
    }
  }

  // Check if operations are still running when app resumes
  Future<void> _checkOperationStatus() async {
    bool isEnabled = await BleAdvertiser.isBluetoothEnabled();
    if (!isEnabled) {
      setState(() {
        _isAdvertising = false;
        _isScanning = false;
      });
    }
  }

  void _toggleAdvertising() async {
    if (_isAdvertising) {
      bool success = await BleAdvertiser.stopAdvertising();
      if (success) {
        setState(() {
          _isAdvertising = false;
        });
      }
    } else {
      bool success = await BleAdvertiser.startAdvertising(
        serviceUuid: _deviceUuid,
        inBackground: _backgroundModeEnabled,
      );
      if (success) {
        setState(() {
          _isAdvertising = true;
        });
      }
    }
  }

  void _toggleScanning() async {
    if (_isScanning) {
      bool success = await BleAdvertiser.stopScanning();
      _scanSubscription?.cancel();

      if (success) {
        setState(() {
          _isScanning = false;
        });
      }
    } else {
      bool success = await BleAdvertiser.startScanning(
        inBackground: _backgroundModeEnabled,
      );

      if (success) {
        setState(() {
          _isScanning = true;
          _discoveredDevices.clear();
        });

        _scanSubscription = BleAdvertiser.scanResults.listen((result) {
          print('Found device: $result');

          // Add or update device in our list
          setState(() {
            int existingIndex = _discoveredDevices.indexWhere((device) =>
                device['deviceId'] == result['deviceId'] &&
                device['serviceUuid'] == result['serviceUuid']);

            if (existingIndex >= 0) {
              // Update existing device (e.g., RSSI value)
              _discoveredDevices[existingIndex] = {
                ..._discoveredDevices[existingIndex],
                ...result
              };
            } else {
              // Add new device
              _discoveredDevices.add(result);
            }
          });
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanSubscription?.cancel();
    BleAdvertiser.stopAdvertising();
    BleAdvertiser.stopScanning();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('BLE Advertiser Demo')),
        body: Padding(
          padding: EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your Device UUID:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text(_deviceUuid),
              SizedBox(height: 16),

              // Background mode switch
              Row(
                children: [
                  Text('Background Mode:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Switch(
                    value: _backgroundModeEnabled,
                    onChanged: (value) {
                      if (Platform.isIOS && !_permissionsGranted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                'Please grant "Always" location permission for background operation'),
                            action: SnackBarAction(
                              label: 'Request',
                              onPressed: requestPermissions,
                            ),
                          ),
                        );
                        return;
                      }

                      setState(() {
                        _backgroundModeEnabled = value;
                      });

                      // Restart operations if they're running
                      if (_isAdvertising) {
                        BleAdvertiser.stopAdvertising();
                        BleAdvertiser.startAdvertising(
                          serviceUuid: _deviceUuid,
                          inBackground: _backgroundModeEnabled,
                        );
                      }

                      if (_isScanning) {
                        _scanSubscription?.cancel();
                        BleAdvertiser.stopScanning();
                        BleAdvertiser.startScanning(
                          inBackground: _backgroundModeEnabled,
                        );
                        _setupScanListener();
                      }
                    },
                  ),
                  Text(_backgroundModeEnabled ? 'Enabled' : 'Disabled'),
                ],
              ),

              SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: _toggleAdvertising,
                    child: Text(_isAdvertising
                        ? 'Stop Advertising'
                        : 'Start Advertising'),
                  ),
                  ElevatedButton(
                    onPressed: _toggleScanning,
                    child:
                        Text(_isScanning ? 'Stop Scanning' : 'Start Scanning'),
                  ),
                ],
              ),
              SizedBox(height: 24),
              Text('Discovered Devices:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Expanded(
                child: _discoveredDevices.isEmpty
                    ? Center(child: Text('No devices found'))
                    : ListView.builder(
                        itemCount: _discoveredDevices.length,
                        itemBuilder: (context, index) {
                          final device = _discoveredDevices[index];
                          return ListTile(
                            title:
                                Text(device['deviceName'] ?? 'Unknown Device'),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('ID: ${device['deviceId']}'),
                                if (device['serviceUuid'] != null &&
                                    device['serviceUuid'].toString().isNotEmpty)
                                  Text('UUID: ${device['serviceUuid']}'),
                              ],
                            ),
                            trailing: Text('RSSI: ${device['rssi']}'),
                          );
                        },
                      ),
              ),

              // Status indicator
              Container(
                padding: EdgeInsets.all(8),
                color: Colors.grey[200],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Status:'),
                    Text(
                        '• Bluetooth ${_isAdvertising || _isScanning ? 'active' : 'inactive'}'),
                    Text(
                        '• Background mode ${_backgroundModeEnabled ? 'enabled' : 'disabled'}'),
                    Text(
                        '• Required permissions ${_permissionsGranted ? 'granted' : 'not granted'}'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setupScanListener() {
    _scanSubscription = BleAdvertiser.scanResults.listen((result) {
      print('Found device: $result');

      setState(() {
        int existingIndex = _discoveredDevices.indexWhere((device) =>
            device['deviceId'] == result['deviceId'] &&
            device['serviceUuid'] == result['serviceUuid']);

        if (existingIndex >= 0) {
          // Update existing device
          _discoveredDevices[existingIndex] = {
            ..._discoveredDevices[existingIndex],
            ...result
          };
        } else {
          // Add new device
          _discoveredDevices.add(result);
        }
      });
    });
  }
}
