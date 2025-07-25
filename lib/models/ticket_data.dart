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

class ComboTicketData {
  final String comboId;
  final String cardNumber;

  const ComboTicketData({required this.comboId, required this.cardNumber});

  factory ComboTicketData.fromJson(Map<String, dynamic> json) {
    return ComboTicketData(
      comboId: json['combo_id'] as String,
      cardNumber: json['card_number'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {'combo_id': comboId, 'card_number': cardNumber};
  }
}
