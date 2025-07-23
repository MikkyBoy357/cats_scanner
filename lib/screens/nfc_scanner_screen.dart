import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:nfc_manager/ndef_record.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager_ndef/nfc_manager_ndef.dart';

import '../main.dart';
import 'result_screen.dart';

class NFCScannerScreen extends StatefulWidget {
  const NFCScannerScreen({super.key});

  @override
  State<NFCScannerScreen> createState() => _NFCScannerScreenState();
}

class _NFCScannerScreenState extends State<NFCScannerScreen> {
  bool isScanning = false;
  String statusText = 'Tap "Start Scanning" to begin';

  @override
  void initState() {
    super.initState();
    _checkNFCAvailability();
    _pingBackend();
  }

  @override
  void dispose() async {
    super.dispose();
    await NfcManager.instance.stopSession();
  }

  Future<void> _pingBackend() async {
    final endpoint = '$baseUrl/api/events';

    try {
      final response = await http.get(Uri.parse(endpoint));
      if (response.statusCode == 200) {
        print('Backend is reachable');
      } else {
        print('Backend returned an error: ${response.statusCode}');
        // show snack bar
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backend returned an error: ${response.statusCode}'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      print('Error pinging backend: $e');
      // show snack bar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error pinging backend: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _checkNFCAvailability() async {
    bool isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable) {
      setState(() {
        statusText = 'NFC is not available on this device';
      });
    }
  }

  Future<void> _startNFCScanning() async {
    setState(() {
      isScanning = true;
      statusText = 'Hold your device near an NFC card...';
    });

    try {
      await NfcManager.instance.startSession(
        pollingOptions: NfcPollingOption.values.toSet(),
        onDiscovered: (NfcTag tag) async {
          // Extract data from NFC tag
          String nfcData = await _extractNFCData(tag);

          // Stop scanning
          await Future.delayed(Duration(milliseconds: 1000));
          await NfcManager.instance.stopSession();

          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    ResultScreen(scannedData: nfcData, scanType: 'NFC Card'),
              ),
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
    // await Future.delayed(Duration(seconds: 3));
    await NfcManager.instance.stopSession();
    setState(() {
      isScanning = false;
      statusText = 'Scanning stopped';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NFC Scanner'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.nfc,
                size: 100,
                color: isScanning ? Colors.green : Colors.grey,
              ),
              const SizedBox(height: 40),
              Text(
                statusText,
                style: const TextStyle(fontSize: 18),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              if (!isScanning)
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: _startNFCScanning,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text(
                      'Start NFC Scanning',
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: _stopNFCScanning,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text(
                      'Stop Scanning',
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
