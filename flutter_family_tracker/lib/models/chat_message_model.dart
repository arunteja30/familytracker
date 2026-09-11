class ChatMessageModel {
  final String messageId;
  final String senderPhone;
  final String senderName;
  final String text;
  final int timestamp;
  final String type; // 'TEXT' or 'LOCATION'
  final double? latitude;
  final double? longitude;
  final String? address;

  const ChatMessageModel({
    required this.messageId,
    required this.senderPhone,
    required this.senderName,
    required this.text,
    required this.timestamp,
    this.type = 'TEXT',
    this.latitude,
    this.longitude,
    this.address,
  });

  bool get isLocation => type == 'LOCATION' && latitude != null && longitude != null;

  factory ChatMessageModel.fromJson(String messageId, Map<dynamic, dynamic> json) {
    return ChatMessageModel(
      messageId: messageId,
      senderPhone: json['senderPhone']?.toString() ?? '',
      senderName: json['senderName']?.toString() ?? 'Family Member',
      text: json['text']?.toString() ?? '',
      timestamp: (json['timestamp'] is num)
          ? (json['timestamp'] as num).toInt()
          : DateTime.now().millisecondsSinceEpoch,
      type: json['type']?.toString() ?? 'TEXT',
      latitude: (json['latitude'] is num) ? (json['latitude'] as num).toDouble() : null,
      longitude: (json['longitude'] is num) ? (json['longitude'] as num).toDouble() : null,
      address: json['address']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'senderPhone': senderPhone,
      'senderName': senderName,
      'text': text,
      'timestamp': timestamp,
      'type': type,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (address != null) 'address': address,
    };
  }
}
