import 'package:cats_scanner/models/scan_entry.dart';
import 'package:cats_scanner/models/ticket_type.dart';

class TicketResponse {
  final String id;
  final Map<String, dynamic> event;
  final TicketType ticketType;
  final Map<String, dynamic> issuedTo;
  final DateTime? issuedAt;
  final String ticketNumber;
  final List<ScanEntry> scanHistory;

  List<ScanEntry> get scansToday {
    final today = DateTime.now();
    return scanHistory.where((scan) {
      final scanDate = scan.scannedAt;
      return scanDate.year == today.year &&
          scanDate.month == today.month &&
          scanDate.day == today.day;
    }).toList();
  }

  TicketResponse({
    required this.id,
    required this.event,
    required this.ticketType,
    required this.issuedTo,
    required this.issuedAt,
    required this.ticketNumber,
    required this.scanHistory,
  });

  factory TicketResponse.fromJson(Map<String, dynamic> json) {
    return TicketResponse(
      id: json['_id'] as String,
      event: json['event'] as Map<String, dynamic>,
      ticketType: TicketType.fromJson(
        json['ticketType'] as Map<String, dynamic>,
      ),
      issuedTo: json['issuedTo'] as Map<String, dynamic>,
      issuedAt: DateTime.tryParse(json['issuedAt'] as String? ?? ''),
      ticketNumber: json['ticketNumber'] as String,
      scanHistory: () {
        final scanHistoryJson = json['scanHistory'] as List<dynamic>?;
        if (scanHistoryJson == null) return <ScanEntry>[];
        return scanHistoryJson.map((entry) {
          return ScanEntry.fromJson(entry as Map<String, dynamic>);
        }).toList();
        return <ScanEntry>[];
      }(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'event': event,
      'ticketType': ticketType,
      'issuedTo': issuedTo,
      'issuedAt': issuedAt.toString(),
      'ticketNumber': ticketNumber,
      'scanHistory': scanHistory,
    };
  }
}
