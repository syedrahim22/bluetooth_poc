import 'package:bluetooth_poc/models/device_request.dart';
import 'package:bluetooth_poc/models/personnel_response.dart';
import 'package:dchs_flutter_beacon/dchs_flutter_beacon.dart';
import 'package:get/get.dart';

class RequirementStateController extends GetxController {
  var bluetoothState = BluetoothState.stateOff.obs;
  var authorizationStatus = AuthorizationStatus.notDetermined.obs;
  var locationService = false.obs;

  final _startBroadcasting = false.obs;
  final startScanning = false.obs;
  final pauseScanning = false.obs;

  bool get bluetoothEnabled => bluetoothState.value == BluetoothState.stateOn;
  bool get authorizationStatusOk =>
      authorizationStatus.value == AuthorizationStatus.allowed ||
      authorizationStatus.value == AuthorizationStatus.always;
  bool get locationServiceEnabled => locationService.value;
  final RxList<DeviceInfo> deviceList = <DeviceInfo>[].obs;
  final RxList<Personnel> personnelDetails = <Personnel>[].obs;

  void addDevice(DeviceInfo device) {
    final exists = deviceList.any((d) =>
        d.type == device.type &&
        d.address == device.address &&
        d.major == device.major &&
        d.minor == device.minor);

    if (!exists) {
      deviceList.add(device);
    }
  }
  void addPersonnelDetails(List<Personnel> details) {
    personnelDetails.clear();
      personnelDetails.addAll(details);
  }

  void clearDevices() {
    deviceList.clear();
  }

  updateBluetoothState(BluetoothState state) {
    bluetoothState.value = state;
  }

  updateAuthorizationStatus(AuthorizationStatus status) {
    authorizationStatus.value = status;
  }

  updateLocationService(bool flag) {
    locationService.value = flag;
  }

  startBroadcasting() {
    _startBroadcasting.value = true;
  }

  stopBroadcasting() {
    _startBroadcasting.value = false;
  }

  startScanningFunc() {
    startScanning.value = true;
    pauseScanning.value = false;
  }

  pauseScanningFunc() {
    startScanning.value = false;
    pauseScanning.value = true;
  }

  Stream<bool> get startBroadcastStream {
    return _startBroadcasting.stream;
  }

  Stream<bool> get startStream {
    return startScanning.stream;
  }

  Stream<bool> get pauseStream {
    return pauseScanning.stream;
  }
}
