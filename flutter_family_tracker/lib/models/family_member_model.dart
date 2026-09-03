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
      name: json['name']?.toString() ?? '',
      mobile: json['mobile']?.toString() ?? '',
      relationship: json['relationship']?.toString() ?? '',
      memberId: json['memberId']?.toString() ?? '',
      familyName: json['familyName']?.toString() ?? '',
      pushNofityToken: json['pushNofityToken']?.toString(),
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
