class TicketData {
  final String ticketId;
  final String ticketNumber;

  const TicketData({required this.ticketId, required this.ticketNumber});

  factory TicketData.fromJson(Map<String, dynamic> json) {
    return TicketData(
      ticketId: json['ticketId'] as String,
      ticketNumber: json['ticketNumber'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {'ticketId': ticketId, 'ticketNumber': ticketNumber};
  }
}
