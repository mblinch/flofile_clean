import 'package:flutter/material.dart';
import '../services/mlb_api_service.dart' show Player;
import '../services/nba_api_service.dart';

/// Dev helper: hit ESPN NBA JSON (same paths as [NbaApiService]).
class ApiTestWidget extends StatefulWidget {
  const ApiTestWidget({super.key});

  @override
  State<ApiTestWidget> createState() => _ApiTestWidgetState();
}

class _ApiTestWidgetState extends State<ApiTestWidget> {
  final NbaApiService _api = NbaApiService();
  String _testResults = '';
  bool _isLoading = false;

  Future<void> _runApiTest() async {
    setState(() {
      _isLoading = true;
      _testResults = 'Running ESPN NBA smoke test...\n';
    });

    try {
      final teams = await _api.fetchAllTeams();
      final first = teams.isNotEmpty ? teams.first.name : null;
      final List<Player> roster =
          first != null ? await _api.fetchTeamRoster(first) : <Player>[];
      setState(() {
        _testResults +=
            '${teams.length} teams; sample roster ($first): ${roster.length} players\nDone.\n';
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
      _testResults = 'Loading teams...\n';
    });

    try {
      final teams = await _api.fetchAllTeams();
      setState(() {
        _testResults += 'Found ${teams.length} teams:\n';
        for (final team in teams.take(10)) {
          _testResults += '  - ${team.name} (id ${team.id})\n';
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

  Future<void> _testRoster() async {
    setState(() {
      _isLoading = true;
      _testResults = 'Loading Lakers roster...\n';
    });

    try {
      final players = await _api.fetchTeamRoster('Los Angeles Lakers');
      setState(() {
        _testResults += '${players.length} players (first 10):\n';
        for (final p in players.take(10)) {
          _testResults += '  - ${p.displayName}\n';
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
        title: const Text('ESPN NBA API Test'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _runApiTest,
                    child: const Text('Smoke test'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _testTeams,
                    child: const Text('Teams'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _testRoster,
                    child: const Text('Lakers roster'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isLoading) const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 16),
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
