// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DeviceLookupRequest _$DeviceLookupRequestFromJson(Map<String, dynamic> json) =>
    DeviceLookupRequest(
      devices: (json['devices'] as List<dynamic>)
          .map((e) => DeviceInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$DeviceLookupRequestToJson(
        DeviceLookupRequest instance) =>
    <String, dynamic>{
      'devices': instance.devices,
    };

DeviceInfo _$DeviceInfoFromJson(Map<String, dynamic> json) => DeviceInfo(
      type: json['type'] as String,
      address: json['address'] as String?,
      major: (json['major'] as num?)?.toInt(),
      minor: (json['minor'] as num?)?.toInt(),
    );

Map<String, dynamic> _$DeviceInfoToJson(DeviceInfo instance) =>
    <String, dynamic>{
      'type': instance.type,
      'address': instance.address,
      'major': instance.major,
      'minor': instance.minor,
    };
