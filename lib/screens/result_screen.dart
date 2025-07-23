import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../main.dart';
import '../models/ticket_data.dart';
import 'home_screen.dart';

class ResultScreen extends StatefulWidget {
  final String scannedData;
  final String scanType;

  const ResultScreen({
    super.key,
    required this.scannedData,
    required this.scanType,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  bool isLoading = true;
  String? apiResponse;
  String? errorMessage;
  String? reasonMessage;
  TicketData? ticketData;

  @override
  void initState() {
    super.initState();

    try {
      final scannedJson =
          jsonDecode(widget.scannedData) as Map<String, dynamic>;
      print('scannedJson With comma: $scannedJson');
      ticketData = TicketData.fromJson(scannedJson);
      _sendToBackend();
    } catch (e) {
      print('Error parsing scanned data: $e');
      errorMessage = 'Invalid ticket data format';
      reasonMessage =
          'Could not parse the scanned data. Please ensure it is in the correct format.';
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _sendToBackend() async {
    print('Send to backend called');
    try {
      // Replace with your actual backend endpoint
      final endpoint = '$baseUrl/api/tickets/action/scan';

      final response = await http.post(
        Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiToken',
        },
        body: jsonEncode({
          "ticketNumber": ticketData?.ticketNumber,
          "eventId": "687e6338bab351f897000000",
        }),
      );

      setState(() {
        isLoading = false;
        if (response.statusCode == 200) {
          apiResponse = response.body;
        } else {
          apiResponse = response.body;
          print(apiResponse);
          errorMessage = 'Error: ${response.statusCode} - ${response.body}';
          final Map<String, dynamic> data =
              jsonDecode(response.body) as Map<String, dynamic>;
          reasonMessage = data['reason'] ?? 'Unknown error';
        }
      });
    } catch (e) {
      print('Error: $e');
      setState(() {
        isLoading = false;
        errorMessage = 'Network error: ${e.toString()}';
        reasonMessage =
            'Please check your internet connection or try again later.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Result'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Scan Type: ${widget.scanType}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Scanned Data:',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        widget.scannedData,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Backend Response:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Card(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16.0),
                  child: isLoading
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 20),
                              Text('Validating ticket...'),
                            ],
                          ),
                        )
                      : errorMessage != null
                      ? SingleChildScrollView(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.error,
                                color: Colors.red,
                                size: 50,
                              ),
                              const SizedBox(height: 20),
                              Text(
                                reasonMessage ?? 'An error occurred',
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 16,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                                size: 50,
                              ),
                              const SizedBox(height: 20),
                              Text(
                                apiResponse ?? 'No response',
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const HomeScreen(),
                        ),
                        (route) => false,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    child: const Text(
                      'Scan Another',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: isLoading ? null : _sendToBackend,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    child: const Text('Retry', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
