import 'package:json_annotation/json_annotation.dart';

part 'personnel_response.g.dart';

@JsonSerializable()
class PersonnelLookupResponse {
  final PersonnelData data;

  PersonnelLookupResponse({required this.data});

  factory PersonnelLookupResponse.fromJson(Map<String, dynamic> json) =>
      _$PersonnelLookupResponseFromJson(json);
}

@JsonSerializable()
class PersonnelData {
  final List<Personnel> personnel;

  PersonnelData({required this.personnel});

  factory PersonnelData.fromJson(Map<String, dynamic> json) =>
      _$PersonnelDataFromJson(json);
}

@JsonSerializable()
class Personnel {
  final int id;
  final String firstName;
  final String lastName;
  final List<Device> devices;

  Personnel({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.devices,
  });

  factory Personnel.fromJson(Map<String, dynamic> json) =>
      _$PersonnelFromJson(json);
}

@JsonSerializable()
class Device {
  final int id;
  final String type;
  final String? address;
  final String deviceName;
  final int? major;
  final int? minor;

  Device({
    required this.id,
    required this.type,
    this.address,
    required this.deviceName,
    this.major,
    this.minor,
  });

  factory Device.fromJson(Map<String, dynamic> json) =>
      _$DeviceFromJson(json);
}
