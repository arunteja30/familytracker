class FamilyMemberModel {
  String name;
  String mobile;
  String relationship;
  String memberId;
  String familyName;
  String? pushNofityToken;
  String? adminName;
  String? password;
  String? message;
  String? gpsInfo;
  String? uid;
  bool isRegistered;

  FamilyMemberModel({
    required this.name,
    required this.mobile,
    this.relationship = '',
    this.memberId = '',
    this.familyName = '',
    this.pushNofityToken,
    this.adminName,
    this.password,
    this.message,
    this.gpsInfo,
    this.uid,
    this.isRegistered = false,
  });

  factory FamilyMemberModel.fromJson(Map<dynamic, dynamic> json) {
    return FamilyMemberModel(
      name: json['name']?.toString() ??
          json['userName']?.toString() ??
          json['adminName']?.toString() ??
          'Member',
      mobile: json['mobile']?.toString() ??
          json['mobileNo']?.toString() ??
          json['phone']?.toString() ??
          json['phoneNumber']?.toString() ??
          '',
      relationship: json['relationship']?.toString() ??
          json['relation']?.toString() ??
          '',
      memberId: json['memberId']?.toString() ??
          json['id']?.toString() ??
          json['uid']?.toString() ??
          '',
      familyName: json['familyName']?.toString() ??
          json['family']?.toString() ??
          json['group']?.toString() ??
          '',
      pushNofityToken: json['pushNofityToken']?.toString() ??
          json['fcmToken']?.toString(),
      adminName: json['adminName']?.toString(),
      password: json['password']?.toString(),
      message: json['message']?.toString(),
      gpsInfo: json['gpsInfo']?.toString(),
      uid: json['uid']?.toString(),
      isRegistered: json['registered'] == true ||
          json['isRegistered'] == true ||
          json['registered']?.toString() == 'true',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'mobile': mobile,
      'relationship': relationship,
      'memberId': memberId,
      'familyName': familyName,
      'pushNofityToken': pushNofityToken,
      'adminName': adminName,
      'password': password,
      'message': message,
      'gpsInfo': gpsInfo,
      'uid': uid,
      'registered': isRegistered,
      'isRegistered': isRegistered,
    };
  }
}
