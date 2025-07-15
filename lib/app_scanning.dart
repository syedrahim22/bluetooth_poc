// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter/material.dart';
import 'dart:async';

import 'package:dchs_flutter_beacon/dchs_flutter_beacon.dart';
import '/controller/requirement_state_controller.dart';
import 'package:get/get.dart';

class TabScanning extends StatefulWidget {
  const TabScanning({super.key});

  @override
  TabScanningState createState() => TabScanningState();
}

class TabScanningState extends State<TabScanning> {
  StreamSubscription<RangingResult>? _streamRanging;
  final _regionBeacons = <Region, List<Beacon>>{};
  final _beacons = <Beacon>[];
  final controller = Get.find<RequirementStateController>();

  @override
  void initState() {
    super.initState();

    controller.startStream.listen((flag) {
      if (flag == true) {
        initScanBeacon();
      }
    });

    controller.pauseStream.listen((flag) {
      if (flag == true) {
        pauseScanBeacon();
      }
    });
  }

  final List<BeaconPerson> knownBeacons = [
    BeaconPerson(
      uuid: 'D68FA139-7E78-4F74-8666-278CB024281F',
      major: 19531,
      minor: 41089,
      personName: 'Raj Verma',
    ),
    BeaconPerson(
      uuid: 'D68FA139-7E78-4F74-8666-278CB024281F',
      major: 40511,
      minor: 23078,
      personName: 'Nishchay Malhan',
    ),
    BeaconPerson(
      uuid: 'D68FA139-7E78-4F74-8666-278CB024281F',
      major: 43462,
      minor: 10549,
      personName: 'Abhishek Kumar',
    ),
    BeaconPerson(
      uuid: 'D68FA139-7E78-4F74-8666-278CB024281F',
      major: 64576,
      minor: 2163,
      personName: 'Alex Verghese',
    ),
  ];
  String? getPersonName({
    required String uuid,
    required int major,
    required int minor,
  }) {
    final match = knownBeacons.firstWhere(
      (beacon) =>
          beacon.uuid.toLowerCase() == uuid.toLowerCase() &&
          beacon.major == major &&
          beacon.minor == minor,
      orElse: () => BeaconPerson(uuid: '', major: 0, minor: 0, personName: ''),
    );

    return match.personName.isEmpty ? null : match.personName;
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

    //await flutterBeacon.setEnableScheduledScanJobs(true);

    await flutterBeacon.initializeScanning;
    if (!controller.authorizationStatusOk ||
        !controller.locationServiceEnabled ||
        !controller.bluetoothEnabled) {
      print(
          'RETURNED, authorizationStatusOk=${controller.authorizationStatusOk}, '
          'locationServiceEnabled=${controller.locationServiceEnabled}, '
          'bluetoothEnabled=${controller.bluetoothEnabled}');
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
      print(result);
      if (mounted) {
        setState(() {
          _regionBeacons[result.region] = result.beacons;
          _beacons.clear();
          for (var list in _regionBeacons.values) {
            _beacons.addAll(list);
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
    _streamRanging?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: Obx(
      () => !controller.bluetoothEnabled
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
              : _beacons.isEmpty
                  ? controller.pauseScanning.value
                      ? const Center(child: Text('No beacons found'))
                      : Center(
                          child: CircularProgressIndicator(),
                        )
                  : ListView(
                      children: ListTile.divideTiles(
                        context: context,
                        tiles: _beacons.map(
                          (beacon) {
                            return ListTile(
                              title: Text(
                                getPersonName(
                                      uuid: beacon.proximityUUID,
                                      major: beacon.major,
                                      minor: beacon.minor,
                                    ) ??
                                    'Unknown',
                                style: const TextStyle(fontSize: 15.0),
                              ),
                              subtitle: Row(
                                mainAxisSize: MainAxisSize.max,
                                children: <Widget>[
                                  Flexible(
                                    flex: 1,
                                    fit: FlexFit.tight,
                                    child: Text(
                                      'UUID: ${beacon.proximityUUID}\nMajor: ${beacon.major}, Minor: ${beacon.minor}',
                                      style: const TextStyle(fontSize: 13.0),
                                    ),
                                  ),
                                  Flexible(
                                    flex: 2,
                                    fit: FlexFit.tight,
                                    child: Text(
                                      'Accuracy: ${beacon.accuracy}m\nRSSI: ${beacon.rssi}',
                                      style: const TextStyle(fontSize: 13.0),
                                    ),
                                  )
                                ],
                              ),
                            );
                          },
                        ),
                      ).toList(),
                    ),
    ));
  }
}

class BeaconPerson {
  final String uuid;
  final int major;
  final int minor;
  final String personName;

  const BeaconPerson({
    required this.uuid,
    required this.major,
    required this.minor,
    required this.personName,
  });
}
