import 'package:json_annotation/json_annotation.dart';

part 'device_request.g.dart';

@JsonSerializable()
class DeviceLookupRequest {
  final List<DeviceInfo> devices;

  DeviceLookupRequest({required this.devices});

  Map<String, dynamic> toJson() => _$DeviceLookupRequestToJson(this);

  factory DeviceLookupRequest.fromJson(Map<String, dynamic> json) =>
      _$DeviceLookupRequestFromJson(json);
}

@JsonSerializable()
class DeviceInfo {
  final String type;
  final String? address;
  final int? major;
  final int? minor;

  DeviceInfo({
    required this.type,
    this.address,
    this.major,
    this.minor,
  });

  Map<String, dynamic> toJson() => _$DeviceInfoToJson(this);

  factory DeviceInfo.fromJson(Map<String, dynamic> json) =>
      _$DeviceInfoFromJson(json);
}
