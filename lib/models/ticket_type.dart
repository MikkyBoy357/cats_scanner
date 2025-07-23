class TicketType {
  String? id;
  double? price;
  String? name;
  String? description;
  int? totalSupply;
  String? visibility;
  String? codePrefix;
  String? createdBy;
  bool? soldOut;
  DateTime? validFrom;
  DateTime? validUntil;
  int? maxScansPerDay;

  TicketType({
    this.id,
    this.price,
    this.name,
    this.description,
    this.totalSupply,
    this.visibility,
    this.codePrefix,
    this.createdBy,
    this.soldOut,
    this.validFrom,
    this.validUntil,
    this.maxScansPerDay,
  });

  TicketType.fromJson(Map<String, dynamic> json) {
    id = json['_id'];
    price = json['price'];
    name = json['name'];
    description = json['description'];
    totalSupply = json['totalSupply'];
    visibility = json['visibility'];
    codePrefix = json['codePrefix'];
    createdBy = json['createdBy'];
    soldOut = json['soldOut'];
    validFrom = DateTime.tryParse(json['validFrom'] as String);
    validUntil = DateTime.tryParse(json['validUntil'] as String);
    maxScansPerDay = json['maxScansPerDay'];
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'price': price,
      'name': name,
      'description': description,
      'totalSupply': totalSupply,
      'visibility': visibility,
      'codePrefix': codePrefix,
      'createdBy': createdBy,
      'soldOut': soldOut,
      'validFrom': validFrom?.toIso8601String(),
      'validUntil': validUntil?.toIso8601String(),
      'maxScansPerDay': maxScansPerDay,
    };
  }
}
