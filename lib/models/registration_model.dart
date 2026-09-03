class RegistrationModel {
  String phone;
  String name;
  String? uid;

  RegistrationModel({
    required this.phone,
    required this.name,
    this.uid,
  });

  factory RegistrationModel.fromJson(Map<dynamic, dynamic> json) {
    return RegistrationModel(
      phone: json['phone']?.toString() ?? json['mobileNo']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      uid: json['uid']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'phone': phone,
      'name': name,
      'uid': uid,
    };
  }
}
