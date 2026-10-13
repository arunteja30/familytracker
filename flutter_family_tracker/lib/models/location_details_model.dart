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
      if (val is num) {
        final n = val.toInt();
        return (n > 0 && n < 10000000000) ? n * 1000 : n;
      }
      final str = val.toString().replaceAll('%', '').trim();
      final n = int.tryParse(str) ?? 0;
      return (n > 0 && n < 10000000000) ? n * 1000 : n;
    }

    return LocationDetailsModel(
      latitude: parseDouble(json['latitude'] ?? json['lat']),
      longitude: parseDouble(json['longitude'] ?? json['lng'] ?? json['lon']),
      timeStamp: parseInt(json['timeStamp'] ?? json['timestamp'] ?? json['time'] ?? json['ts'] ?? json['timeKey']),
      date: json['date']?.toString() ?? '',
      batteryPercentage: parseInt(json['batteryPercentage'] ?? json['battery']),
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
