import 'dart:convert';
import 'package:bluetooth_poc/models/device_request.dart';
import 'package:bluetooth_poc/models/personnel_response.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

Future<PersonnelLookupResponse?> lookupPersonnelDevices(List<DeviceInfo> devices) async {
  final url = Uri.parse('https://systematic-aqua-wolverine.pams.revolte.io/api/v1/personnel/devices/lookup');

  try {
    final requestBody = DeviceLookupRequest(devices: devices).toJson();

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(requestBody),
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return PersonnelLookupResponse.fromJson(json);
    } else {
      if (kDebugMode) {
        print('API Error: ${response.statusCode} ${response.body}');
      }
    }
  } catch (e) {
    if (kDebugMode) {
      print('Network Error: $e');
    }
  }

  return null;
}
