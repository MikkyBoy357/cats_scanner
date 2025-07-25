import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:nfc_manager/ndef_record.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager_ndef/nfc_manager_ndef.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../models/ticket_data.dart';
import '../models/ticket_response.dart';

enum MyModalStatus { success, loading, error, cardReadError, forbidden }

class NFCScannerScreen extends StatefulWidget {
  const NFCScannerScreen({super.key});

  @override
  State<NFCScannerScreen> createState() => _NFCScannerScreenState();
}

class _NFCScannerScreenState extends State<NFCScannerScreen>
    with TickerProviderStateMixin {
  bool isScanning = false;
  bool isNFCAvailable = false;
  String statusText = 'Initializing NFC...';

  late AnimationController _waveController;
  late AnimationController _pulseController;
  late Animation<double> _waveAnimation1;
  late Animation<double> _waveAnimation2;
  late Animation<double> _waveAnimation3;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _checkNFCAvailability();
    _pingBackend();
  }

  void _initializeAnimations() {
    // Wave animation controller
    _waveController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    // Pulse animation controller
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    // Multiple wave animations with different delays
    _waveAnimation1 = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _waveController, curve: Curves.easeOut));

    _waveAnimation2 = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _waveController,
        curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
      ),
    );

    _waveAnimation3 = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _waveController,
        curve: const Interval(0.6, 1.0, curve: Curves.easeOut),
      ),
    );

    // Pulse animation for the main circle
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Start animations when scanning
    _waveController.repeat();
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() async {
    _waveController.dispose();
    _pulseController.dispose();
    await NfcManager.instance.stopSession();
    super.dispose();
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

  Future<void> _checkNFCAvailability() async {
    bool isAvailable = await NfcManager.instance.isAvailable();
    setState(() {
      isNFCAvailable = isAvailable;
    });

    if (isAvailable) {
      _startNFCScanning();
    } else {
      setState(() {
        statusText = 'NFC is not available on this device';
      });
    }
  }

  Future<void> _startNFCScanning() async {
    setState(() {
      isScanning = true;
      statusText = 'Press and get an NFC closer to your device';
    });

    try {
      await NfcManager.instance.startSession(
        pollingOptions: NfcPollingOption.values.toSet(),
        onDiscovered: (NfcTag tag) async {
          // Extract data from NFC tag
          String nfcData;
          Map<String, dynamic> scannedJson;
          TicketData? ticketData;

          try {
            nfcData = await _extractNFCData(tag);
            scannedJson = jsonDecode(nfcData) as Map<String, dynamic>;
            print('scannedJson With comma: $scannedJson');
            ticketData = TicketData.fromJson(scannedJson);

            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (context) {
                return TicketModal(modalStatus: MyModalStatus.loading);
              },
            );
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

          if (ticketData == null) {
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

          // Stop scanning
          await Future.delayed(const Duration(milliseconds: 1000));
          await NfcManager.instance.stopSession();

          // fetch ticket data from backend
          final endpoint = '$baseUrl/api/tickets/view/${ticketData.ticketId}';
          try {
            final response = await http.get(Uri.parse(endpoint));
            print(response.body);
            if (response.statusCode == 200) {
              final responseJson = jsonDecode(response.body);
              print('=========> ${responseJson.runtimeType}');
              final ticketResponse = TicketResponse.fromJson(responseJson);
              log('Ticket Response: $responseJson');

              // dismiss modal if it is still open
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              }

              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (context) {
                  return TicketDetailsModal(ticketResponse: ticketResponse);
                },
              ).then((_) async {
                print('====> Restart');
                await _stopNFCScanning();
                await _startNFCScanning();
              });
            } else {
              // dismiss modal if it is still open
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              }
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
            // dismiss modal if it is still open
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            }
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
        },
      );
    } catch (e) {
      setState(() {
        isScanning = false;
        statusText = 'Error: ${e.toString()}';
      });
    }
  }

  Future<String> _extractNFCData(NfcTag tag) async {
    try {
      // Try to read NDEF data first (most common format for storing text data)
      final ndef = Ndef.from(tag);
      if (ndef != null) {
        final ndefMessage = await ndef.read();
        if (ndefMessage != null && ndefMessage.records.isNotEmpty) {
          // Extract text from NDEF records
          String extractedData = '';
          for (var record in ndefMessage.records) {
            // Handle well-known type records
            if (record.typeNameFormat == TypeNameFormat.wellKnown) {
              // Handle text records (TNF=1, Type='T')
              if (record.type.isNotEmpty && record.type[0] == 0x54) {
                // 'T' for text
                if (record.payload.isNotEmpty) {
                  // Skip language code (first few bytes) and get the actual text
                  final languageCodeLength = record.payload[0] & 0x3F;
                  if (record.payload.length > 1 + languageCodeLength) {
                    final textBytes = record.payload.sublist(
                      1 + languageCodeLength,
                    );
                    extractedData += String.fromCharCodes(textBytes);
                  }
                }
              }
              // Handle URI records (TNF=1, Type='U')
              else if (record.type.isNotEmpty && record.type[0] == 0x55) {
                // 'U' for URI
                if (record.payload.isNotEmpty) {
                  final uriBytes = record.payload.sublist(
                    1,
                  ); // Skip URI identifier code
                  extractedData += String.fromCharCodes(uriBytes);
                }
              }
            }
            // Handle other record types or raw data
            else {
              // For raw data, convert payload to string
              try {
                if (record.payload.isNotEmpty) {
                  // Try to decode as UTF-8 string
                  final stringData = String.fromCharCodes(record.payload);
                  // Check if it's printable text
                  if (stringData.runes.every(
                    (rune) =>
                        rune >= 32 && rune <= 126 || rune == 10 || rune == 13,
                  )) {
                    extractedData += stringData;
                  } else {
                    // If not printable, use hex representation
                    extractedData += record.payload
                        .map((e) => e.toRadixString(16).padLeft(2, '0'))
                        .join(' ');
                  }
                }
              } catch (e) {
                // If conversion fails, use hex representation
                if (record.payload.isNotEmpty) {
                  extractedData += record.payload
                      .map((e) => e.toRadixString(16).padLeft(2, '0'))
                      .join(' ');
                }
              }
            }
          }
          if (extractedData.isNotEmpty) {
            print('NDEF Data extracted: $extractedData');
            return extractedData.trim();
          }
        }
      }
      return 'Unknown NFC tag detected';
    } catch (e) {
      print('Error extracting NFC data: $e');
      return 'Error reading NFC data: ${e.toString()}';
    }
  }

  Future<void> _stopNFCScanning() async {
    await NfcManager.instance.stopSession();
    setState(() {
      isScanning = false;
      statusText = 'Scanning stopped';
    });
  }

  Widget _buildWaveCircle(
    Animation<double> animation,
    double maxRadius,
    Color color,
  ) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Container(
          width: maxRadius * 2 * animation.value,
          height: maxRadius * 2 * animation.value,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withOpacity(1.0 - animation.value),
              width: 2.0,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Register NFC Tag'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            _stopNFCScanning();
            Navigator.pop(context);
          },
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              icon: const Icon(Icons.notifications, color: Colors.black),
              onPressed: () {},
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // NFC Info Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3CD),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE066),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.nfc,
                          color: Colors.black,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'NFC',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'This feature will allow you communicate with an NFC device and show the details of an item. To test it out you need a NFC',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF8B7355),
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // NFC Scanning Circle with Wave Animation
                Center(
                  child: Column(
                    children: [
                      SizedBox(
                        width: 300,
                        height: 300,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Wave circles
                            if (isScanning) ...[
                              _buildWaveCircle(
                                _waveAnimation1,
                                150,
                                Colors.grey,
                              ),
                              _buildWaveCircle(
                                _waveAnimation2,
                                150,
                                Colors.grey,
                              ),
                              _buildWaveCircle(
                                _waveAnimation3,
                                150,
                                Colors.grey,
                              ),
                            ],
                            // Main NFC Circle with pulse animation
                            AnimatedBuilder(
                              animation: _pulseAnimation,
                              builder: (context, child) {
                                return Transform.scale(
                                  scale: isScanning
                                      ? _pulseAnimation.value
                                      : 1.0,
                                  child: Container(
                                    width: 160,
                                    height: 160,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.black,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.3),
                                          blurRadius: isScanning ? 20 : 10,
                                          spreadRadius: isScanning ? 5 : 2,
                                        ),
                                      ],
                                    ),
                                    child: const Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.nfc,
                                          color: Colors.white,
                                          size: 40,
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          'NFC',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 40),
                      Text(
                        statusText,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomSheet: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: () {
              _stopNFCScanning();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ),
            child: const Text(
              'Annuler',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}

// Beautiful Ticket Details Modal
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
                        final endpoint = '$baseUrl/api/tickets/action/scan';
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

// Enhanced Modal with Success and Forbidden states
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
                  Icons.nfc_outlined,
                  size: 50,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Card Read Error',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Unable to read NFC card data. Please try again.',
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
