// ignore_for_file: use_build_context_synchronously

import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:permission_handler/permission_handler.dart';
// import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

SizedBox getSpace(double height, double width) {
  return SizedBox(height: height, width: width);
}

class BlueetoothPage extends StatefulWidget {
  const BlueetoothPage({super.key});

  static const String routePath = '/bluetooth_page';

  @override
  State<BlueetoothPage> createState() => _BlueetoothPageState();
}

class _BlueetoothPageState extends State<BlueetoothPage> {
  bool isBluetoothOn = false;
  List<ScanResult> scanResults = <ScanResult>[];
  bool isScanning = false;
  bool isAdvertising = false;

  Future<String> getOrCreateUniqueId() async {
    return Uuid().v4();
  }

  final AdvertiseSetParameters advertiseSetParameters = AdvertiseSetParameters(
    includeTxPowerLevel: true, // Include power level in advertisement
  );

  bool _isSupported = false;

  @override
  void initState() {
    super.initState();
    requestPermissions();
    initPlatformState();

    // Listen to scan results
    FlutterBluePlus.scanResults.listen((List<ScanResult> results) {
      setState(() {
        scanResults = results;
      });
      log(results.toString());
      // ignore: inference_failure_on_untyped_parameter, always_specify_types
    }, onError: (e) {
      log('Scan error: $e');
    });

    // Listen to Bluetooth state changes
    FlutterBluePlus.adapterState.listen((BluetoothAdapterState state) {
      if (state == BluetoothAdapterState.on) {
        log('Bluetooth is on');
        isBluetoothOn = true;
        setState(() {});
      } else if (state == BluetoothAdapterState.off) {
        log('Bluetooth is off');
        isBluetoothOn = false;
        setState(() {});
        // Stop scanning if Bluetooth is turned off
        if (isScanning) {
          stopScan();
        }
      }
    });
  }

  Future<void> initPlatformState() async {
    final bool isSupported = await FlutterBlePeripheral().isSupported;
    setState(() {
      _isSupported = isSupported;
    });
  }

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

  // Turn on Bluetooth
  Future<void> turnOnBluetooth() async {
    if (await FlutterBluePlus.isSupported) {
      await FlutterBluePlus.turnOn();
    } else {
      log('Bluetooth is not available on this device');
    }
  }

  // Start scanning for devices
  Future<void> startScan() async {
    if (await FlutterBluePlus.isSupported) {
      if (await FlutterBluePlus.adapterState.first ==
          BluetoothAdapterState.on) {
        setState(() {
          scanResults = <ScanResult>[];
          isScanning = true;
        });

        try {
          await FlutterBluePlus.startScan(
            timeout: const Duration(seconds: 15),
            androidScanMode: AndroidScanMode.balanced,
            // Optional: Add specific service UUIDs if known
            // withServices: <Guid>[
            // Add any specific service UUIDs the iPhone might be using
            // ],
          );
        } catch (e) {
          log('Start scan error: $e');
        } finally {
          setState(() {
            isScanning = false;
          });
        }
      } else {
        log('Bluetooth is off');
        showBluetoothSettingsDialog();
      }
    } else {
      log('Bluetooth is not available on this device');
    }
  }

  // Handle Bluetooth toggle
  Future<void> handleBluetoothToggle() async {
    if (!isBluetoothOn) {
      if (Platform.isAndroid) {
        try {
          await FlutterBluePlus.turnOn();
        } catch (e) {
          log('Error turning on Bluetooth: $e');
          showBluetoothSettingsDialog();
        }
      } else if (Platform.isIOS) {
        // For iOS, show settings instructions
        showBluetoothSettingsDialog();
      }
    } else {
      showBluetoothSettingsDialog();
    }
  }

  // Show dialog with instructions to change Bluetooth settings
  void showBluetoothSettingsDialog() {
    showDialog<AlertDialog>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Bluetooth Settings'),
        content: Text(
          isBluetoothOn
              ? 'Please turn off Bluetooth through your device settings.'
              : 'Please turn on Bluetooth through your device settings.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // Stop scanning for devices
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    setState(() {
      isScanning = false;
    });
  }

  Future<void> _requestPermissions() async {
    final hasPermission = await FlutterBlePeripheral().hasPermission();
    switch (hasPermission) {
      case BluetoothPeripheralState.denied:
        print("We don't have permissions, requesting now!");

        await _requestPermissions();
        break;
      default:
        print("State: $hasPermission!");

        break;
    }
  }

  Future<void> _hasPermissions() async {
    final hasPermissions = await FlutterBlePeripheral().hasPermission();
    print("Has permission: $hasPermissions");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: isScanning ? stopScan : startScan,
        child: Icon(isScanning ? Icons.stop : Icons.search),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
          child: Column(
            // shrinkWrap: true,
            children: <Widget>[
              const Text(
                'Bluetooth POC Implementation Page',
              ),
              getSpace(20.h, 0),
              Text(
                'Is advertising data supported: $_isSupported',
              ),
              getSpace(20.h, 0),
              Row(
                children: <Widget>[
                  const Text(
                    'Bluetooth On/Off',
                  ),
                  getSpace(0, 20.w),
                  Switch(
                    value: isBluetoothOn,
                    onChanged: (bool value) {
                      if (value) {
                        turnOnBluetooth();
                      } else {
                        // Note: Directly turning off Bluetooth programmatically is limited on iOS
                        // Show settings instructions for iOS
                        showDialog<AlertDialog>(
                          context: context,
                          builder: (BuildContext context) => AlertDialog(
                            title: const Text('Turn off Bluetooth'),
                            content: const Text(
                                'On iOS, please turn off Bluetooth through Settings manually.'),
                            actions: <Widget>[
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('OK'),
                              ),
                            ],
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
              getSpace(20.h, 0),
              StreamBuilder<PeripheralState>(
                stream: FlutterBlePeripheral().onPeripheralStateChanged,
                initialData: PeripheralState.unknown,
                builder:
                    (BuildContext context, AsyncSnapshot<dynamic> snapshot) {
                  return Text(
                    'State: ${(snapshot.data as PeripheralState).name}',
                  );
                },
              ),
              getSpace(10.h, 0),
              MaterialButton(
                onPressed: () async {
                  final uuid = await getOrCreateUniqueId();
                  log(uuid);

                  final data = Uint8List.fromList([0x01, 0x02, 0x03]);
                  final AdvertiseData advertiseData = AdvertiseData(
                    includeDeviceName: true,
                    serviceUuid: uuid,
                    // serviceDataUuid: uuid, // Optional
                    // serviceData: 'Extra Service Data'.codeUnits,
                    manufacturerId: 1234,
                    manufacturerData: data, // This is a List<int>
                  );

                  try {
                    await FlutterBlePeripheral().start(
                      advertiseData: advertiseData,
                      advertiseSetParameters: advertiseSetParameters,
                    );
                    setState(() {
                      isAdvertising = true;
                    });
                    log('Started advertising');
                  } catch (e) {
                    log('Error starting advertising: $e');
                  }
                },
                color: Colors.blue,
                textColor: Colors.white,
                child: Text(
                    isAdvertising ? 'Stop Advertising' : 'Start Advertising'),
              ),

              MaterialButton(
                onPressed: () async {
                  await FlutterBlePeripheral().stop();
                },
                child: Text(
                  'Stop advertising',
                  style: Theme.of(context)
                      .primaryTextTheme
                      .labelLarge!
                      .copyWith(color: Colors.blue),
                ),
              ),
              MaterialButton(
                onPressed: _requestPermissions,
                child: Text(
                  'Request Permissions',
                  style: Theme.of(context)
                      .primaryTextTheme
                      .labelLarge!
                      .copyWith(color: Colors.blue),
                ),
              ),
              MaterialButton(
                onPressed: _hasPermissions,
                child: Text(
                  'Has permissions',
                  style: Theme.of(context)
                      .primaryTextTheme
                      .labelLarge!
                      .copyWith(color: Colors.blue),
                ),
              ),
              getSpace(20.h, 0),
              // Text('Current UUID: ${advertiseData.serviceUuid}'),
              getSpace(20.h, 0),
              Expanded(
                child: scanResults.isEmpty
                    ? Center(
                        child: isScanning
                            ? const CircularProgressIndicator()
                            : const Text(
                                'No devices found. Tap scan to start.'),
                      )
                    : ListView.builder(
                        itemCount: scanResults.length,
                        itemBuilder: (BuildContext context, int index) {
                          final ScanResult result = scanResults[index];
                          return ListTile(
                            title: Text(result.advertisementData.advName),
                            subtitle: Text(
                                '${result.device.remoteId.str} ${result.device}'),
                            trailing: Text('${result.rssi} dBm'),
                            onTap: () {},
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
