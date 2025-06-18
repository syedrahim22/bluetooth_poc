// pubspec.yaml dependencies:
/*
dependencies:
  flutter:
    sdk: flutter
  uuid: ^4.0.0
  shared_preferences: ^2.2.2
*/

// // main.dart
import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

// void main() {
//   runApp(MyApp());
// }

// class MyApp extends StatelessWidget {
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'BLE Advertiser Scanner',
//       theme: ThemeData(
//         primarySwatch: Colors.blue,
//         visualDensity: VisualDensity.adaptivePlatformDensity,
//       ),
//       home: BLEHomePage(),
//     );
//   }
// }

class BLEHomePage extends StatefulWidget {
  @override
  _BLEHomePageState createState() => _BLEHomePageState();
}

class _BLEHomePageState extends State<BLEHomePage> with WidgetsBindingObserver {
  static const platform = MethodChannel('ble_advertiser_scanner');

  // State variables
  bool _isAdvertising = false;
  bool _isScanning = false;
  bool _backgroundModeEnabled = false;
  String _currentAdvertisingUUID = '';
  String _bluetoothState = 'unknown';
  String _peripheralState = 'unknown';
  String _locationAuthStatus = 'unknown';

  List<Map<String, dynamic>> _scannedDevices = [];
  final TextEditingController _uuidController = TextEditingController();
  final Uuid _uuidGenerator = Uuid();

  // Timers and streams
  Timer? _statusUpdateTimer;
  StreamController<String> _logStreamController =
      StreamController<String>.broadcast();
  List<String> _logMessages = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupMethodChannelHandler();
    _loadSavedUUID();
    _checkInitialStates();
    _startStatusUpdateTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusUpdateTimer?.cancel();
    _logStreamController.close();
    _uuidController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _addLog('App lifecycle state: ${state.toString()}');

    if (state == AppLifecycleState.paused) {
      _addLog('App backgrounded - BLE operations should continue');
    } else if (state == AppLifecycleState.resumed) {
      _addLog('App foregrounded - refreshing status');
      _refreshAllStates();
    }
  }

  void _setupMethodChannelHandler() {
    platform.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onDeviceDiscovered':
          _handleDeviceDiscovered(call.arguments);
          break;
        case 'onAdvertisingStarted':
          setState(() {
            _isAdvertising = true;
            _currentAdvertisingUUID = call.arguments['uuid'] ?? '';
          });
          _addLog('Advertising started: ${_currentAdvertisingUUID}');
          break;
        case 'onAdvertisingStopped':
          setState(() {
            _isAdvertising = false;
            _currentAdvertisingUUID = '';
          });
          _addLog('Advertising stopped');
          break;
        case 'onScanningStarted':
          setState(() => _isScanning = true);
          _addLog('Scanning started');
          break;
        case 'onScanningStopped':
          setState(() => _isScanning = false);
          _addLog('Scanning stopped');
          break;
        case 'onBluetoothStateChanged':
          setState(() => _bluetoothState = call.arguments['state']);
          _addLog('Bluetooth state: ${_bluetoothState}');
          break;
        case 'onPeripheralStateChanged':
          setState(() => _peripheralState = call.arguments['state']);
          _addLog('Peripheral state: ${_peripheralState}');
          break;
        case 'onLocationAuthorizationChanged':
          setState(() => _locationAuthStatus = call.arguments['status']);
          _addLog('Location auth: ${_locationAuthStatus}');
          break;
        case 'onBackgroundModeEnabled':
          setState(() => _backgroundModeEnabled = true);
          _addLog('Background mode enabled');
          break;
        case 'onBackgroundModeDisabled':
          setState(() => _backgroundModeEnabled = false);
          _addLog('Background mode disabled');
          break;
        case 'onAdvertisingError':
          _addLog('Advertising error: ${call.arguments['error']}');
          break;
      }
    });
  }

  void _handleDeviceDiscovered(dynamic arguments) {
    final deviceInfo = Map<String, dynamic>.from(arguments);

    setState(() {
      // Remove existing device with same ID and add updated one
      _scannedDevices.removeWhere((device) => device['id'] == deviceInfo['id']);
      _scannedDevices.insert(0, deviceInfo);

      // Limit to 50 devices to prevent memory issues
      if (_scannedDevices.length > 50) {
        _scannedDevices = _scannedDevices.take(50).toList();
      }
    });

    _addLog(
        'Device discovered: ${deviceInfo['name']} (${deviceInfo['rssi']} dBm)');
  }

  void _addLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    final logMessage = '[$timestamp] $message';

    setState(() {
      _logMessages.insert(0, logMessage);
      if (_logMessages.length > 100) {
        _logMessages = _logMessages.take(100).toList();
      }
    });

    _logStreamController.add(logMessage);
    print(logMessage);
  }

  Future<void> _loadSavedUUID() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUUID = prefs.getString('last_uuid');
    if (savedUUID != null && savedUUID.isNotEmpty) {
      _uuidController.text = savedUUID;
    } else {
      // Generate a default UUID
      _uuidController.text = _uuidGenerator.v4().toUpperCase();
    }
  }

  Future<void> _saveUUID(String uuid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_uuid', uuid);
  }

  Future<void> _checkInitialStates() async {
    try {
      _isAdvertising = await platform.invokeMethod('isAdvertising') ?? false;
      _isScanning = await platform.invokeMethod('isScanning') ?? false;

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

  void _startStatusUpdateTimer() {
    _statusUpdateTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      _refreshAllStates();
    });
  }

  Future<void> _refreshAllStates() async {
    try {
      final isAdv = await platform.invokeMethod('isAdvertising') ?? false;
      final isScn = await platform.invokeMethod('isScanning') ?? false;

      setState(() {
        _isAdvertising = isAdv;
        _isScanning = isScn;
      });
    } catch (e) {
      _addLog('Error refreshing states: $e');
    }
  }

  Future<void> _startAdvertising() async {
    final uuid = _uuidController.text.trim();
    if (uuid.isEmpty) {
      _showSnackBar('Please enter a UUID');
      return;
    }

    try {
      if(Platform.isIOS){
        await platform.invokeMethod('startAdvertising', {'uuid': uuid});
      }else{
        await platform.invokeMethod('startAdvertising', {'serviceUuid': uuid});
      }
      await _saveUUID(uuid);
      _addLog('Start advertising requested: $uuid');
    } catch (e) {
      _addLog('Error starting advertising: $e');
      _showSnackBar('Failed to start advertising: $e');
    }
  }

  Future<void> _stopAdvertising() async {
    try {
      await platform.invokeMethod('stopAdvertising');
      _addLog('Stop advertising requested');
    } catch (e) {
      _addLog('Error stopping advertising: $e');
      _showSnackBar('Failed to stop advertising: $e');
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

  Future<void> _clearScannedDevices() async {
    try {
      await platform.invokeMethod('clearScannedDevices');
      setState(() => _scannedDevices.clear());
      _addLog('Scanned devices cleared');
    } catch (e) {
      _addLog('Error clearing devices: $e');
      _showSnackBar('Failed to clear devices: $e');
    }
  }

  Future<void> _toggleBackgroundMode() async {
    try {
      if (_backgroundModeEnabled) {
        await platform.invokeMethod('disableBackgroundMode');
        _addLog('Background mode disable requested');
      } else {
        await platform.invokeMethod('enableBackgroundMode');
        _addLog('Background mode enable requested');
      }
    } catch (e) {
      _addLog('Error toggling background mode: $e');
      _showSnackBar('Failed to toggle background mode: $e');
    }
  }

  void _generateNewUUID() {
    _uuidController.text = _uuidGenerator.v4().toUpperCase();
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

  Color _getStateColor(String state) {
    switch (state.toLowerCase()) {
      case 'poweredon':
        return Colors.green;
      case 'poweredoff':
        return Colors.red;
      case 'authorized':
      case 'authorizedalways':
        return Colors.green;
      case 'denied':
      case 'unauthorized':
        return Colors.red;
      default:
        return Colors.orange;
    }
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
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12),
            color: Colors.grey[100],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _StatusChip('BLE', _bluetoothState,
                        _getStateColor(_bluetoothState)),
                    SizedBox(width: 8),
                    _StatusChip('Peripheral', _peripheralState,
                        _getStateColor(_peripheralState)),
                    SizedBox(width: 8),
                    _StatusChip('Location', _locationAuthStatus,
                        _getStateColor(_locationAuthStatus)),
                  ],
                ),
                SizedBox(height: 8),
                Row(
                  children: [
                    _StatusChip('Advertising', _isAdvertising ? 'ON' : 'OFF',
                        _isAdvertising ? Colors.green : Colors.grey),
                    SizedBox(width: 8),
                    _StatusChip('Scanning', _isScanning ? 'ON' : 'OFF',
                        _isScanning ? Colors.green : Colors.grey),
                    SizedBox(width: 8),
                    _StatusChip(
                        'Background',
                        _backgroundModeEnabled ? 'ON' : 'OFF',
                        _backgroundModeEnabled ? Colors.blue : Colors.grey),
                  ],
                ),
              ],
            ),
          ),

          // Main Content
          Expanded(
            child: DefaultTabController(
              length: 3,
              child: Column(
                children: [
                  TabBar(
                    labelColor: Colors.blue,
                    unselectedLabelColor: Colors.grey,
                    tabs: [
                      Tab(text: 'Advertise'),
                      Tab(text: 'Scan (${_scannedDevices.length})'),
                      Tab(text: 'Logs'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildAdvertiseTab(),
                        _buildScanTab(),
                        _buildLogsTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdvertiseTab() {
    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'UUID to Advertise',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _uuidController,
                          decoration: InputDecoration(
                            labelText: 'Service UUID',
                            border: OutlineInputBorder(),
                            hintText: 'Enter UUID or generate new one',
                          ),
                          onChanged: (value) => _saveUUID(value),
                        ),
                      ),
                      SizedBox(width: 8),
                      IconButton(
                        onPressed: _generateNewUUID,
                        icon: Icon(Icons.refresh),
                        tooltip: 'Generate New UUID',
                      ),
                    ],
                  ),
                  if (_currentAdvertisingUUID.isNotEmpty) ...[
                    SizedBox(height: 12),
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.green[200]!),
                      ),
                      child: Text(
                        'Currently advertising: $_currentAdvertisingUUID',
                        style:
                            TextStyle(color: Colors.green[800], fontSize: 12),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isAdvertising ? null : _startAdvertising,
                  icon: Icon(Icons.broadcast_on_personal),
                  label: Text('Start Advertising'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: !_isAdvertising ? null : _stopAdvertising,
                  icon: Icon(Icons.stop),
                  label: Text('Stop Advertising'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _toggleBackgroundMode,
            icon: Icon(_backgroundModeEnabled ? Icons.pause : Icons.play_arrow),
            label: Text(_backgroundModeEnabled
                ? 'Disable Background Mode'
                : 'Enable Background Mode'),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  _backgroundModeEnabled ? Colors.orange : Colors.blue,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: 12),
            ),
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
                  onPressed: _isScanning ? null : _startScanning,
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
                  onPressed: !_isScanning ? null : _stopScanning,
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

        // Clear Button
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _scannedDevices.isEmpty ? null : _clearScannedDevices,
              icon: Icon(Icons.clear_all),
              label: Text('Clear All Devices'),
            ),
          ),
        ),

        SizedBox(height: 8),

        // Device List
        Expanded(
          child: _scannedDevices.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.bluetooth_searching,
                          size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        _isScanning
                            ? 'Scanning for devices...'
                            : 'No devices found',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                      if (!_isScanning)
                        Text(
                          'Start scanning to discover BLE devices',
                          style:
                              TextStyle(fontSize: 14, color: Colors.grey[600]),
                        ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _scannedDevices.length,
                  itemBuilder: (context, index) {
                    final device = _scannedDevices[index];
                    return _buildDeviceCard(device);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildDeviceCard(Map<String, dynamic> device) {
    final name = device['name'] ?? 'Unknown Device';
    final id = device['id'] ?? '';
    final rssi = device['rssi'] ?? 0;
    final serviceUUIDs = List<String>.from(device['serviceUUIDs'] ?? []);
    final timestamp = device['timestamp'];

    final lastSeen = timestamp != null
        ? DateTime.fromMillisecondsSinceEpoch((timestamp * 1000).round())
        : DateTime.now();

    final timeDiff = DateTime.now().difference(lastSeen);
    final lastSeenText = timeDiff.inSeconds < 60
        ? '${timeDiff.inSeconds}s ago'
        : '${timeDiff.inMinutes}m ago';

    return Card(
      margin: EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getRSSIColor(rssi),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${rssi} dBm',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
            SizedBox(height: 4),
            Text(
              'ID: ${id.substring(0, 8)}...',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            Text(
              'Last seen: $lastSeenText',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            if (serviceUUIDs.isNotEmpty) ...[
              SizedBox(height: 8),
              Text(
                'Service UUIDs:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              ...serviceUUIDs.map((uuid) => Padding(
                    padding: EdgeInsets.only(left: 8, top: 2),
                    child: Text(
                      uuid,
                      style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Colors.blue[700]),
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLogsTab() {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() => _logMessages.clear());
              },
              icon: Icon(Icons.clear),
              label: Text('Clear Logs'),
            ),
          ),
        ),
        Expanded(
          child: _logMessages.isEmpty
              ? Center(
                  child: Text(
                    'No logs yet',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _logMessages.length,
                  itemBuilder: (context, index) {
                    return Container(
                      padding: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      margin: EdgeInsets.only(bottom: 2),
                      decoration: BoxDecoration(
                        color: index.isEven ? Colors.grey[50] : Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _logMessages[index],
                        style: TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Color _getRSSIColor(int rssi) {
    if (rssi >= -50) return Colors.green;
    if (rssi >= -70) return Colors.orange;
    return Colors.red;
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatusChip(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color.withOpacity(0.8),
        ),
      ),
    );
  }
}
