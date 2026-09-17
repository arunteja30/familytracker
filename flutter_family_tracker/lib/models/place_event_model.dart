class PlaceEventModel {
  String id;
  String familyName;
  String placeId;
  String placeName;
  String memberName;
  String memberMobile;
  String eventType; // 'entered' or 'left'
  int timestamp;

  PlaceEventModel({
    required this.id,
    required this.familyName,
    required this.placeId,
    required this.placeName,
    required this.memberName,
    required this.memberMobile,
    required this.eventType,
    int? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  bool get isArrival => eventType == 'entered';

  factory PlaceEventModel.fromJson(Map<dynamic, dynamic> json, [String? fallbackId]) {
    return PlaceEventModel(
      id: json['id']?.toString() ?? fallbackId ?? '',
      familyName: json['familyName']?.toString() ?? '',
      placeId: json['placeId']?.toString() ?? '',
      placeName: json['placeName']?.toString() ?? 'Safe Zone',
      memberName: json['memberName']?.toString() ?? 'Family Member',
      memberMobile: json['memberMobile']?.toString() ?? '',
      eventType: json['eventType']?.toString() ?? 'entered',
      timestamp: json['timestamp'] is num
          ? (json['timestamp'] as num).toInt()
          : (int.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now().millisecondsSinceEpoch),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'familyName': familyName,
      'placeId': placeId,
      'placeName': placeName,
      'memberName': memberName,
      'memberMobile': memberMobile,
      'eventType': eventType,
      'timestamp': timestamp,
    };
  }
}
