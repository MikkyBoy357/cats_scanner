import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../models/ticket_data.dart';
import '../models/ticket_response.dart';

enum MyModalStatus { success, loading, error, cardReadError, forbidden }

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;
  bool isScanning = true;

  @override
  void reassemble() {
    super.reassemble();
    if (Platform.isAndroid) {
      controller!.pauseCamera();
    } else if (Platform.isIOS) {
      controller!.resumeCamera();
    }
  }

  Future<void> _pingBackend() async {
    final endpoint = '$baseUrl/api/events';
    try {
      final response = await http.get(Uri.parse(endpoint));
      if (response.statusCode == 200) {
        print('Backend is reachable');
      } else {
        print('Backend returned an error: ${response.statusCode}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Backend returned an error: ${response.statusCode}',
              ),
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      print('Error pinging backend: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error pinging backend: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _pingBackend();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR Scanner'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            onPressed: () async {
              await controller?.toggleFlash();
              setState(() {});
            },
            icon: FutureBuilder(
              future: controller?.getFlashStatus(),
              builder: (context, snapshot) {
                return Icon(
                  snapshot.data == true ? Icons.flash_on : Icons.flash_off,
                );
              },
            ),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            flex: 5,
            child: QRView(
              key: qrKey,
              onQRViewCreated: _onQRViewCreated,
              overlay: QrScannerOverlayShape(
                borderColor: Colors.blue,
                borderRadius: 10,
                borderLength: 30,
                borderWidth: 10,
                cutOutSize: 300,
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Container(
              padding: const EdgeInsets.all(20),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Point your camera at a QR code',
                    style: TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'The scan will happen automatically',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onQRViewCreated(QRViewController controller) {
    this.controller = controller;
    controller.scannedDataStream.listen((scanData) {
      if (isScanning && scanData.code != null) {
        setState(() {
          isScanning = false;
        });
        _processQRData(scanData.code!);
      }
    });
  }

  String? _tryFixInvalidJson(String raw) {
    print('RAW ->');
    if (!raw.contains(':')) return null;

    final colonIndex = raw.indexOf(':');
    final prefix = raw.substring(0, colonIndex).trim();
    var content = raw.substring(colonIndex + 1).trim();
    print('content1 -> $content');

    // Clean prefix (e.g., remove "CARD:")

    // replace first empty space with `: `
    content = content.replaceFirst(' ', ' "');
    print('content2 -> $content');

    // replace first comma with `",`
    content = content.replaceFirst(',', '",');
    print('content3 -> $content');

    return content;
  }

  Future<void> _processQRData(String qrData) async {
    Map<String, dynamic> scannedJson;
    ComboTicketData? ticketData;

    print('QR Data: $qrData');

    // Attempt initial parsing
    try {
      scannedJson = jsonDecode(qrData) as Map<String, dynamic>;
      print('scannedJson: $scannedJson');
    } catch (e) {
      // Try to fix malformed input (e.g., starts with "CARD:")
      final fixed = _tryFixInvalidJson(qrData);
      if (fixed != null) {
        try {
          scannedJson = jsonDecode(fixed) as Map<String, dynamic>;
          print('fixed scannedJson: $scannedJson');
        } catch (e) {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) {
              return TicketModal(modalStatus: MyModalStatus.cardReadError);
            },
          );
          return;
        }
      } else {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) {
            return TicketModal(modalStatus: MyModalStatus.cardReadError);
          },
        );
        return;
      }
    }

    try {
      ticketData = ComboTicketData.fromJson(scannedJson);
      print('Parsed ComboTicketData: $ticketData');
    } catch (e) {
      print('Error parsing ComboTicketData: $e');
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) {
          return TicketModal(modalStatus: MyModalStatus.cardReadError);
        },
      );
      return;
    }

    // Make API call
    final endpoint = '$baseUrl/api/comboTickets/number/${ticketData.cardNumber}'
        .replaceAll(' ', '%20');
    try {
      final response = await http.get(Uri.parse(endpoint));
      print(endpoint);
      if (response.statusCode == 200) {
        final responseJson = jsonDecode(response.body);
        final ticketResponse = TicketResponse.fromJson(responseJson);

        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }

        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) =>
              TicketDetailsModal(ticketResponse: ticketResponse),
        ).then((_) => setState(() => isScanning = true));
      } else {
        print('Error Fetching Ticket: ${response.statusCode}');
        if (Navigator.canPop(context)) Navigator.pop(context);
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) {
            return TicketModal(modalStatus: MyModalStatus.error);
          },
        );
      }
    } catch (e) {
      if (Navigator.canPop(context)) Navigator.pop(context);
      print('Error Fetching Ticket: $e');
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) {
          return TicketModal(modalStatus: MyModalStatus.error);
        },
      );
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }
}

// Beautiful Ticket Details Modal (same as NFC)
class TicketDetailsModal extends StatelessWidget {
  final TicketResponse ticketResponse;

  const TicketDetailsModal({super.key, required this.ticketResponse});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 100),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          const SizedBox(height: 24),

          // Success Icon
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle,
              size: 50,
              color: Colors.green,
            ),
          ),

          const SizedBox(height: 20),

          // Title
          const Text(
            'Ticket Found',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'Valid ticket detected',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),

          const SizedBox(height: 32),

          // Ticket Details Card
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              children: [
                _buildDetailRow(
                  'Ticket Number',
                  ticketResponse.ticketNumber,
                  Icons.confirmation_number,
                  Colors.blue,
                ),
                const SizedBox(height: 16),
                _buildDetailRow(
                  'Ticket Type',
                  ticketResponse.ticketType.name.toString(),
                  Icons.local_activity,
                  Colors.purple,
                ),
                const SizedBox(height: 16),
                _buildDetailRow(
                  'Description',
                  ticketResponse.ticketType.description.toString(),
                  Icons.description,
                  Colors.orange,
                ),
                const SizedBox(height: 16),
                _buildDetailRow(
                  'Usage Today',
                  ticketResponse.ticketType.maxScansPerDay == null
                      ? 'ILLIMITÉ'
                      : '${ticketResponse.scansToday.length}/${ticketResponse.ticketType.maxScansPerDay}',
                  Icons.today,
                  Colors.green,
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Action Buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(color: Colors.grey[300]!),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Close',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      showModalBottomSheet(
                        isScrollControlled: true,
                        context: context,
                        backgroundColor: Colors.transparent,
                        builder: (context) {
                          return TicketModal(
                            modalStatus: MyModalStatus.loading,
                          );
                        },
                      );

                      String? reasonMessage;

                      // validate ticket
                      try {
                        // Replace with your actual backend endpoint
                        final endpoint =
                            '$baseUrl/api/comboTickets/action/scan';
                        final sharedPrefs =
                            await SharedPreferences.getInstance();
                        final token = sharedPrefs.getString('authToken');
                        final response = await http.post(
                          Uri.parse(endpoint),
                          headers: {
                            'Content-Type': 'application/json',
                            'Authorization': 'Bearer $token',
                          },
                          body: jsonEncode({
                            "ticketNumber": ticketResponse.ticketNumber,
                            "eventId": "687e6338bab351f897000000",
                          }),
                        );

                        log('Scan Response: ${response.body}');
                        final Map<String, dynamic> data =
                            jsonDecode(response.body) as Map<String, dynamic>;
                        log('Scan Response Type: ${data.runtimeType}');
                        reasonMessage = data['reason'] ?? 'Unknown error';

                        // dismiss loading modal if it is still open
                        if (Navigator.canPop(context)) {
                          Navigator.pop(context);
                        }

                        if (response.statusCode == 200 ||
                            response.statusCode == 201) {
                          print('=========> 201');
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (context) {
                              return TicketModal(
                                modalStatus: MyModalStatus.success,
                              );
                            },
                          );
                        } else if (response.statusCode == 403) {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (context) {
                              return TicketModal(
                                modalStatus: MyModalStatus.forbidden,
                                reason: reasonMessage,
                              );
                            },
                          );
                        } else {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (context) {
                              return TicketModal(
                                modalStatus: MyModalStatus.error,
                                reason: reasonMessage,
                              );
                            },
                          );
                        }
                      } catch (e) {
                        // dismiss loading modal if it is still open
                        if (Navigator.canPop(context)) {
                          Navigator.pop(context);
                        }
                        print('Error: $e');
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (context) {
                            return TicketModal(
                              modalStatus: MyModalStatus.error,
                              reason:
                                  'Network error: Please check your connection',
                            );
                          },
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'VALIDER',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.black,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Enhanced Modal with Success and Forbidden states (same as NFC)
class TicketModal extends StatelessWidget {
  final MyModalStatus modalStatus;
  final String? reason;

  const TicketModal({super.key, required this.modalStatus, this.reason});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 200),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(bottom: 24),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Icon and content based on status
            if (modalStatus == MyModalStatus.loading) ...[
              const SizedBox(
                width: 60,
                height: 60,
                child: CircularProgressIndicator(
                  strokeWidth: 4,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Processing...',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Please wait...',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ] else if (modalStatus == MyModalStatus.success) ...[
              // Success state with green check icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle,
                  size: 50,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Success!',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Ticket validated successfully',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // Dismiss all modals and return to scanning
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ] else if (modalStatus == MyModalStatus.forbidden) ...[
              // Forbidden state with padlock emoji and different theme
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(
                    0xFFE91E63,
                  ).withOpacity(0.1), // Pink/Magenta theme
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Text('🔒', style: TextStyle(fontSize: 40)),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Access Denied',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                reason ?? 'This ticket cannot be validated at this time',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(
                      0xFFE91E63,
                    ), // Pink/Magenta theme
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Try Again',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ] else if (modalStatus == MyModalStatus.error) ...[
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.error_outline,
                  size: 50,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Error',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                reason ?? 'Unable to process ticket. Please try again.',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Try Again',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ] else if (modalStatus == MyModalStatus.cardReadError) ...[
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.qr_code_scanner,
                  size: 50,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'QR Code Read Error',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Unable to read QR code data. Please try again.',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Try Again',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
