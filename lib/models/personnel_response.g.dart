// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'personnel_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PersonnelLookupResponse _$PersonnelLookupResponseFromJson(
        Map<String, dynamic> json) =>
    PersonnelLookupResponse(
      data: PersonnelData.fromJson(json['data'] as Map<String, dynamic>),
    );


PersonnelData _$PersonnelDataFromJson(Map<String, dynamic> json) =>
    PersonnelData(
      personnel: (json['personnel'] as List<dynamic>)
          .map((e) => Personnel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );


Personnel _$PersonnelFromJson(Map<String, dynamic> json) => Personnel(
      id: (json['id'] as num).toInt(),
      firstName: json['firstName'] as String,
      lastName: json['lastName'] as String,
      devices: (json['devices'] as List<dynamic>)
          .map((e) => Device.fromJson(e as Map<String, dynamic>))
          .toList(),
    );


Device _$DeviceFromJson(Map<String, dynamic> json) => Device(
      id: (json['id'] as num).toInt(),
      type: json['type'] as String,
      address: json['address'] as String?,
      deviceName: json['deviceName'] as String,
      major: (json['major'] as num?)?.toInt(),
      minor: (json['minor'] as num?)?.toInt(),
    );

