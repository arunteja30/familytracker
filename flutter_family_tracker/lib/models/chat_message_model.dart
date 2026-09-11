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
  final bool isEdited;
  final int? editedTimestamp;

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
    this.isEdited = false,
    this.editedTimestamp,
  });

  bool get isLocation => type == 'LOCATION' && latitude != null && longitude != null;

  ChatMessageModel copyWith({
    String? messageId,
    String? senderPhone,
    String? senderName,
    String? text,
    int? timestamp,
    String? type,
    double? latitude,
    double? longitude,
    String? address,
    bool? isEdited,
    int? editedTimestamp,
  }) {
    return ChatMessageModel(
      messageId: messageId ?? this.messageId,
      senderPhone: senderPhone ?? this.senderPhone,
      senderName: senderName ?? this.senderName,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      type: type ?? this.type,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
      isEdited: isEdited ?? this.isEdited,
      editedTimestamp: editedTimestamp ?? this.editedTimestamp,
    );
  }

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
      isEdited: json['isEdited'] == true || json['edited'] == true,
      editedTimestamp: (json['editedTimestamp'] is num)
          ? (json['editedTimestamp'] as num).toInt()
          : null,
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
      if (isEdited) 'isEdited': true,
      if (editedTimestamp != null) 'editedTimestamp': editedTimestamp,
    };
  }
}
