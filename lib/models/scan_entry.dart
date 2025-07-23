class ScanEntry {
  DateTime scannedAt;
  bool success; // True if scan was successful, false if it was an error
  String? message; // Message in case of error

  ScanEntry({required this.scannedAt, required this.success, this.message});

  factory ScanEntry.fromJson(Map<String, dynamic> json) {
    return ScanEntry(
      scannedAt: DateTime.parse(json['scannedAt'].toString()),
      success: bool.tryParse(json['success'].toString()) ?? false,
      message: json['message'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'scannedAt': scannedAt.toString(),
      'success': success,
      'message': message,
    };
  }
}
