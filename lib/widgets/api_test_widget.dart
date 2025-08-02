import 'package:flutter/material.dart';
import '../services/balldontlie_api_service.dart';

class ApiTestWidget extends StatefulWidget {
  const ApiTestWidget({super.key});

  @override
  State<ApiTestWidget> createState() => _ApiTestWidgetState();
}

class _ApiTestWidgetState extends State<ApiTestWidget> {
  final BalldontlieApiService _apiService = BalldontlieApiService();
  String _testResults = '';
  bool _isLoading = false;

  Future<void> _runApiTest() async {
    setState(() {
      _isLoading = true;
      _testResults = 'Running API test...\n';
    });

    try {
      // Capture console output by redirecting print statements
      final results = await _apiService.testApiComparison();
      setState(() {
        _testResults += '\nTest completed successfully!';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _testResults += '\nError: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _testTeams() async {
    setState(() {
      _isLoading = true;
      _testResults = 'Testing teams...\n';
    });

    try {
      final teams = await _apiService.fetchAllTeams();
      setState(() {
        _testResults += 'Found ${teams.length} teams:\n';
        for (final team in teams.take(10)) {
          _testResults += '  - ${team.displayName} (${team.location})\n';
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _testResults += 'Error: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _testPlayers() async {
    setState(() {
      _isLoading = true;
      _testResults = 'Testing active players...\n';
    });

    try {
      final players = await _apiService.fetchAllActivePlayers();
      setState(() {
        _testResults += 'Found ${players.length} active players:\n';
        for (final player in players.take(10)) {
          _testResults +=
              '  - ${player.displayName} (${player.position ?? 'N/A'}) - ${player.teamName ?? 'No Team'}\n';
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _testResults += 'Error: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Balldontlie.io API Test'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Test buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _runApiTest,
                    child: const Text('Run Full Test'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _testTeams,
                    child: const Text('Test Teams'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _testPlayers,
                    child: const Text('Test Players'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Loading indicator
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(),
              ),

            const SizedBox(height: 16),

            // Results display
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _testResults.isEmpty
                        ? 'Click a test button to start...'
                        : _testResults,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
