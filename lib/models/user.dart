class User {
  String? id;
  String? name;
  String? userType;
  String? username;
  String? createdBy;

  User({this.id, this.name, this.userType, this.username, this.createdBy});

  User.fromJson(Map<String, dynamic> json) {
    id = json['_id'];
    name = json['name'];
    userType = json['userType'];
    username = json['username'];
    createdBy = json['createdBy'];
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'name': name,
      'userType': userType,
      'username': username,
      'createdBy': createdBy,
    };
  }
}
