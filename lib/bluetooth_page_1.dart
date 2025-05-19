import 'dart:async';
import 'dart:developer';
import 'dart:io';
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

  /// Start advertising with the given service UUID
  static Future<bool> startAdvertising({required String serviceUuid}) async {
    try {
      return await _channel.invokeMethod('startAdvertising', {
        'serviceUuid': serviceUuid,
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
  static Future<bool> startScanning() async {
    try {
      return await _channel.invokeMethod('startScanning');
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

  /// Get a stream of scan results
  static Stream<Map<String, dynamic>> get scanResults {
    _scanResultsStream ??= _scanResultsChannel
        .receiveBroadcastStream()
        .map((dynamic event) => Map<String, dynamic>.from(event));
    return _scanResultsStream!;
  }
}

class BleAdvetiseApp extends StatefulWidget {
  @override
  _BleAdvetiseAppState createState() => _BleAdvetiseAppState();
}

class _BleAdvetiseAppState extends State<BleAdvetiseApp> {
  String _deviceUuid = '';
  bool _isAdvertising = false;
  bool _isScanning = false;
  List<Map<String, dynamic>> _discoveredDevices = [];
  StreamSubscription? _scanSubscription;

  Future<void> requestPermissions() async {
    // Request location permissions (required for Bluetooth scanning on Android)
    if (Platform.isAndroid) {
      final Map<Permission, PermissionStatus> statuses = await <Permission>[
        Permission.location,
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
      ].request();

      if (await Permission.bluetoothScan.isGranted) {
        // return true;
      } else {
        await Permission.bluetoothScan.request();
        return;
      }

      log('Android permission statuses: $statuses');
    } else if (Platform.isIOS) {
      // iOS only needs bluetooth permissions
      final Map<Permission, PermissionStatus> statuses =
          await <PermissionWithService>[
        Permission.bluetooth,
      ].request();

      log('iOS permission statuses: $statuses');
    }
  }

  @override
  void initState() {
    super.initState();
    requestPermissions();
    // Generate a unique ID for this device
    _deviceUuid = BleAdvertiser.generateUniqueUuid();
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
      bool success =
          await BleAdvertiser.startAdvertising(serviceUuid: _deviceUuid);
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
      bool success = await BleAdvertiser.startScanning();

      if (success) {
        setState(() {
          _isScanning = true;
          _discoveredDevices.clear();
        });

        _scanSubscription = BleAdvertiser.scanResults.listen((result) {
          print('Found device: $result');

          // Check if this device is already in our list
          bool deviceExists = _discoveredDevices.any((device) =>
              device['deviceId'] == result['deviceId'] &&
              device['serviceUuid'] == result['serviceUuid']);

          if (!deviceExists) {
            setState(() {
              _discoveredDevices.add(result);
            });
          }
        });
      }
    }
  }

  @override
  void dispose() {
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
                                Text('UUID: ${device['serviceUuid']}'),
                              ],
                            ),
                            trailing: Text('RSSI: ${device['rssi']}'),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
