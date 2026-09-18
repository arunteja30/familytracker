class LocationDetailsModel {
  double latitude;
  double longitude;
  int timeStamp;
  String date;
  int batteryPercentage;
  String address;
  String message;
  String gpsStatus;
  double speedKmh;
  double heading;

  LocationDetailsModel({
    this.latitude = 0.0,
    this.longitude = 0.0,
    this.timeStamp = 0,
    this.date = '',
    this.batteryPercentage = 0,
    this.address = '',
    this.message = '',
    this.gpsStatus = '',
    this.speedKmh = 0.0,
    this.heading = 0.0,
  });

  bool get isMoving => speedKmh >= 5.0;
  String get formattedSpeed => '${speedKmh.round()} km/h';

  factory LocationDetailsModel.fromJson(Map<dynamic, dynamic> json) {
    double parseDouble(dynamic val) {
      if (val == null) return 0.0;
      if (val is num) return val.toDouble();
      return double.tryParse(val.toString()) ?? 0.0;
    }

    int parseInt(dynamic val) {
      if (val == null) return 0;
      if (val is num) return val.toInt();
      final str = val.toString().replaceAll('%', '').trim();
      return int.tryParse(str) ?? 0;
    }

    return LocationDetailsModel(
      latitude: parseDouble(json['latitude']),
      longitude: parseDouble(json['longitude']),
      timeStamp: parseInt(json['timeStamp']),
      date: json['date']?.toString() ?? '',
      batteryPercentage: parseInt(json['batteryPercentage']),
      address: json['address']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      gpsStatus: json['gpsStatus']?.toString() ?? '',
      speedKmh: parseDouble(json['speedKmh'] ?? json['speed']),
      heading: parseDouble(json['heading'] ?? json['bearing']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'timeStamp': timeStamp,
      'date': date,
      'batteryPercentage': batteryPercentage,
      'address': address,
      'message': message,
      'gpsStatus': gpsStatus,
      'speedKmh': speedKmh,
      'heading': heading,
    };
  }
}
