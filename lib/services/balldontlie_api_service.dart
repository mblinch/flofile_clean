import 'dart:convert';
import 'package:http/http.dart' as http;

class BalldontliePlayer {
  final String id;
  final String firstName;
  final String lastName;
  final String? jerseyNumber;
  final String? position;
  final String? teamName;
  final String? teamId;

  BalldontliePlayer({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.jerseyNumber,
    this.position,
    this.teamName,
    this.teamId,
  });

  String get fullName => '$firstName $lastName';
  String get displayName =>
      jerseyNumber != null ? '$fullName #$jerseyNumber' : fullName;

  factory BalldontliePlayer.fromJson(Map<String, dynamic> json) {
    return BalldontliePlayer(
      id: json['id'].toString(),
      firstName: json['first_name'] as String,
      lastName: json['last_name'] as String,
      jerseyNumber: json['jersey']?.toString(),
      position: json['position'] as String?,
      teamName: json['team']?['name'] as String?,
      teamId: json['team']?['id']?.toString(),
    );
  }
}

class BalldontlieTeam {
  final String id;
  final String slug;
  final String abbreviation;
  final String displayName;
  final String shortDisplayName;
  final String name;
  final String location;
  final String league;
  final String division;
  final String? venue;

  BalldontlieTeam({
    required this.id,
    required this.slug,
    required this.abbreviation,
    required this.displayName,
    required this.shortDisplayName,
    required this.name,
    required this.location,
    required this.league,
    required this.division,
    this.venue,
  });

  factory BalldontlieTeam.fromJson(Map<String, dynamic> json) {
    return BalldontlieTeam(
      id: json['id'].toString(),
      slug: json['slug'] as String,
      abbreviation: json['abbreviation'] as String,
      displayName: json['display_name'] as String,
      shortDisplayName: json['short_display_name'] as String,
      name: json['name'] as String,
      location: json['location'] as String,
      league: json['league'] as String,
      division: json['division'] as String,
      venue: json['venue'] as String?,
    );
  }
}

class BalldontlieApiService {
  static const String _baseUrl = 'api.balldontlie.io';
  static const String _apiKey = 'f081f205-1993-4171-8c06-06694c6ae8a4';

  /// Fetches all MLB teams
  Future<List<BalldontlieTeam>> fetchAllTeams() async {
    try {
      final url = Uri.https(_baseUrl, '/mlb/v1/teams');
      final response = await http.get(
        url,
        headers: {'Authorization': _apiKey},
      );

      if (response.statusCode != 200) {
        throw Exception('Team lookup failed: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      final teamsData = data['data'] as List<dynamic>;

      return teamsData
          .map((teamJson) => BalldontlieTeam.fromJson(teamJson))
          .toList();
    } catch (e) {
      print('Error fetching teams: $e');
      rethrow;
    }
  }

  /// Fetches all active players
  Future<List<BalldontliePlayer>> fetchAllActivePlayers() async {
    try {
      final url = Uri.https(_baseUrl, '/mlb/v1/players/active');
      final response = await http.get(
        url,
        headers: {'Authorization': _apiKey},
      );

      if (response.statusCode != 200) {
        throw Exception('Active player lookup failed: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      final playersData = data['data'] as List<dynamic>;

      return playersData
          .map((playerJson) => BalldontliePlayer.fromJson(playerJson))
          .toList();
    } catch (e) {
      print('Error fetching active players: $e');
      rethrow;
    }
  }

  /// Fetches active players for a specific team
  Future<List<BalldontliePlayer>> fetchTeamActivePlayers(String teamId) async {
    try {
      final url =
          Uri.https(_baseUrl, '/mlb/v1/players/active', {'team_ids[]': teamId});
      final response = await http.get(
        url,
        headers: {'Authorization': _apiKey},
      );

      if (response.statusCode != 200) {
        throw Exception(
            'Team active players lookup failed: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      final playersData = data['data'] as List<dynamic>;

      return playersData
          .map((playerJson) => BalldontliePlayer.fromJson(playerJson))
          .toList();
    } catch (e) {
      print('Error fetching team active players: $e');
      rethrow;
    }
  }

  /// Finds a team by name (case-insensitive)
  Future<BalldontlieTeam?> findTeamByName(String teamName) async {
    try {
      final teams = await fetchAllTeams();
      return teams.firstWhere(
        (team) => team.displayName.toLowerCase() == teamName.toLowerCase(),
        orElse: () => throw Exception('Team "$teamName" not found'),
      );
    } catch (e) {
      print('Error finding team $teamName: $e');
      return null;
    }
  }

  /// Fetches venue information for a specific game on a specific date
  Future<String?> fetchVenueForGame(
      String homeTeam, String awayTeam, DateTime gameDate) async {
    try {
      // Find both teams to get their IDs
      final homeTeamInfo = await findTeamByName(homeTeam);
      final awayTeamInfo = await findTeamByName(awayTeam);

      if (homeTeamInfo == null || awayTeamInfo == null) {
        print('Could not find team info for $homeTeam or $awayTeam');
        return null;
      }

      // Format date for API (YYYY-MM-DD)
      final dateString =
          '${gameDate.year}-${gameDate.month.toString().padLeft(2, '0')}-${gameDate.day.toString().padLeft(2, '0')}';

      // Fetch games for the specific date and teams
      final url = Uri.https(_baseUrl, '/mlb/v1/games', {
        'dates[]': dateString,
        'team_ids[]': homeTeamInfo.id,
        'team_ids[]': awayTeamInfo.id,
      });

      final response = await http.get(
        url,
        headers: {'Authorization': _apiKey},
      );

      if (response.statusCode != 200) {
        print('Error fetching games for venue: ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body);
      final gamesData = data['data'] as List<dynamic>;

      if (gamesData.isNotEmpty) {
        final game = gamesData.first;
        final venue = game['venue'] as String?;
        final homeTeamName = game['home_team_name'] as String?;
        final awayTeamName = game['away_team_name'] as String?;

        print(
            'Found game: $awayTeamName @ $homeTeamName on $dateString at $venue');
        return venue;
      }

      print('No games found for $awayTeam @ $homeTeam on $dateString');
      return null;
    } catch (e) {
      print('Error fetching venue for game: $e');
      return null;
    }
  }

  /// Fetches venue information for a specific team by looking up recent games
  Future<String?> fetchVenueForTeam(String teamName) async {
    try {
      // First, find the team to get its ID
      final team = await findTeamByName(teamName);
      if (team == null) return null;

      // Fetch recent games for this team to get venue information
      final url = Uri.https(_baseUrl, '/mlb/v1/games', {
        'team_ids[]': team.id,
        'per_page': '1', // Just get the most recent game
      });

      final response = await http.get(
        url,
        headers: {'Authorization': _apiKey},
      );

      if (response.statusCode != 200) {
        print('Error fetching games for venue: ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body);
      final gamesData = data['data'] as List<dynamic>;

      if (gamesData.isNotEmpty) {
        final game = gamesData.first;
        final venue = game['venue'] as String?;
        print('Found venue for $teamName: $venue');
        return venue;
      }

      return null;
    } catch (e) {
      print('Error fetching venue for team $teamName: $e');
      return null;
    }
  }

  /// Test function to compare with MLB API
  Future<void> testApiComparison() async {
    print('=== Balldontlie.io MLB API Test ===');

    try {
      // Test fetching teams
      print('\n1. Testing team fetch...');
      final teams = await fetchAllTeams();
      print('Found ${teams.length} teams');
      print('Sample teams:');
      for (int i = 0; i < teams.length.clamp(0, 5); i++) {
        print('  - ${teams[i].displayName} (${teams[i].location})');
      }

      // Test fetching active players
      print('\n2. Testing active player fetch...');
      final players = await fetchAllActivePlayers();
      print('Found ${players.length} active players');
      print('Sample players:');
      for (int i = 0; i < players.length.clamp(0, 5); i++) {
        final player = players[i];
        print(
            '  - ${player.displayName} (${player.position ?? 'N/A'}) - ${player.teamName ?? 'No Team'}');
      }

      // Test team-specific players
      if (teams.isNotEmpty) {
        print('\n3. Testing team-specific active players...');
        final firstTeam = teams.first;
        final teamPlayers = await fetchTeamActivePlayers(firstTeam.id);
        print(
            'Found ${teamPlayers.length} active players for ${firstTeam.name}');
        print('Sample team players:');
        for (int i = 0; i < teamPlayers.length.clamp(0, 3); i++) {
          final player = teamPlayers[i];
          print('  - ${player.displayName} (${player.position ?? 'N/A'})');
        }
      }
    } catch (e) {
      print('Error during API test: $e');
    }
  }
}
