import 'game_info.dart';

/// Home city for a league team name, used by caption previews.
class TeamHomePlace {
  const TeamHomePlace({
    required this.city,
    required this.region,
    required this.regionCode,
    required this.country,
    required this.countryCode,
  });

  final String city;
  final String region;
  final String regionCode;
  final String country;
  final String countryCode;

  bool get isUnitedStates =>
      countryCode == 'USA' || countryCode == 'US';

  GameInfo applyTo(GameInfo base) {
    final sameCity =
        base.city.trim().toLowerCase() == city.trim().toLowerCase();
    return base.copyWith(
      city: city,
      region: region,
      regionCode: regionCode,
      country: country,
      countryCode: countryCode,
      venue: sameCity ? base.venue : '',
    );
  }
}

const _us = TeamHomePlace(
  city: '',
  region: '',
  regionCode: '',
  country: 'United States',
  countryCode: 'USA',
);

const _ca = TeamHomePlace(
  city: '',
  region: '',
  regionCode: '',
  country: 'Canada',
  countryCode: 'CAN',
);

TeamHomePlace _usPlace(String city, String region, String code) => TeamHomePlace(
      city: city,
      region: region,
      regionCode: code,
      country: _us.country,
      countryCode: _us.countryCode,
    );

TeamHomePlace _caPlace(String city, String region, String code) => TeamHomePlace(
      city: city,
      region: region,
      regionCode: code,
      country: _ca.country,
      countryCode: _ca.countryCode,
    );

/// Resolves a display team name (for example "Toronto Maple Leafs") to the
/// city used in a caption. Returns null when the name is not a known club.
TeamHomePlace? teamHomePlace(String teamName) {
  final key = teamName.trim().toLowerCase();
  if (key.isEmpty) return null;
  final exact = _exact[key];
  if (exact != null) return exact;
  for (final entry in _prefixes) {
    if (key.startsWith(entry.$1)) return entry.$2;
  }
  return null;
}

final Map<String, TeamHomePlace> _exact = {
  'toronto maple leafs': _caPlace('Toronto', 'Ontario', 'ON'),
  'toronto blue jays': _caPlace('Toronto', 'Ontario', 'ON'),
  'toronto raptors': _caPlace('Toronto', 'Ontario', 'ON'),
  'toronto fc': _caPlace('Toronto', 'Ontario', 'ON'),
  'toronto tempo': _caPlace('Toronto', 'Ontario', 'ON'),
  'montreal canadiens': _caPlace('Montreal', 'Quebec', 'QC'),
  'cf montréal': _caPlace('Montreal', 'Quebec', 'QC'),
  'cf montreal': _caPlace('Montreal', 'Quebec', 'QC'),
  'vancouver canucks': _caPlace('Vancouver', 'British Columbia', 'BC'),
  'vancouver whitecaps': _caPlace('Vancouver', 'British Columbia', 'BC'),
  'calgary flames': _caPlace('Calgary', 'Alberta', 'AB'),
  'edmonton oilers': _caPlace('Edmonton', 'Alberta', 'AB'),
  'ottawa senators': _caPlace('Ottawa', 'Ontario', 'ON'),
  'winnipeg jets': _caPlace('Winnipeg', 'Manitoba', 'MB'),
  'golden state warriors': _usPlace('San Francisco', 'California', 'CA'),
  'golden state valkyries': _usPlace('San Francisco', 'California', 'CA'),
  'utah jazz': _usPlace('Salt Lake City', 'Utah', 'UT'),
  'brooklyn nets': _usPlace('Brooklyn', 'New York', 'NY'),
  'vegas golden knights': _usPlace('Las Vegas', 'Nevada', 'NV'),
  'las vegas aces': _usPlace('Las Vegas', 'Nevada', 'NV'),
  'arizona diamondbacks': _usPlace('Phoenix', 'Arizona', 'AZ'),
  'arizona coyotes': _usPlace('Phoenix', 'Arizona', 'AZ'),
  'carolina hurricanes': _usPlace('Raleigh', 'North Carolina', 'NC'),
  'florida panthers': _usPlace('Sunrise', 'Florida', 'FL'),
  'colorado avalanche': _usPlace('Denver', 'Colorado', 'CO'),
  'colorado rockies': _usPlace('Denver', 'Colorado', 'CO'),
  'colorado rapids': _usPlace('Denver', 'Colorado', 'CO'),
  'texas rangers': _usPlace('Arlington', 'Texas', 'TX'),
  'tampa bay lightning': _usPlace('Tampa', 'Florida', 'FL'),
  'tampa bay rays': _usPlace('St. Petersburg', 'Florida', 'FL'),
  'minnesota wild': _usPlace('Saint Paul', 'Minnesota', 'MN'),
  'minnesota timberwolves': _usPlace('Minneapolis', 'Minnesota', 'MN'),
  'minnesota twins': _usPlace('Minneapolis', 'Minnesota', 'MN'),
  'minnesota lynx': _usPlace('Minneapolis', 'Minnesota', 'MN'),
  'minnesota united fc': _usPlace('Saint Paul', 'Minnesota', 'MN'),
  'new england revolution': _usPlace('Foxborough', 'Massachusetts', 'MA'),
  'inter miami cf': _usPlace('Fort Lauderdale', 'Florida', 'FL'),
  'la galaxy': _usPlace('Los Angeles', 'California', 'CA'),
  'lafc': _usPlace('Los Angeles', 'California', 'CA'),
  'fc cincinnati': _usPlace('Cincinnati', 'Ohio', 'OH'),
  'fc dallas': _usPlace('Dallas', 'Texas', 'TX'),
  'd.c. united': _usPlace('Washington', 'District of Columbia', 'DC'),
  'real salt lake': _usPlace('Sandy', 'Utah', 'UT'),
  'red bull new york': _usPlace('Harrison', 'New Jersey', 'NJ'),
  'sporting kansas city': _usPlace('Kansas City', 'Kansas', 'KS'),
  'oakland athletics': _usPlace('Oakland', 'California', 'CA'),
  'washington nationals': _usPlace('Washington', 'District of Columbia', 'DC'),
  'washington capitals': _usPlace('Washington', 'District of Columbia', 'DC'),
  'washington wizards': _usPlace('Washington', 'District of Columbia', 'DC'),
  'washington mystics': _usPlace('Washington', 'District of Columbia', 'DC'),
  'connecticut sun': _usPlace('Uncasville', 'Connecticut', 'CT'),
  'indiana pacers': _usPlace('Indianapolis', 'Indiana', 'IN'),
  'indiana fever': _usPlace('Indianapolis', 'Indiana', 'IN'),
};

/// Longest prefix first so "san francisco" wins over "san".
final List<(String, TeamHomePlace)> _prefixes = _prefixEntries()
  ..sort((a, b) => b.$1.length.compareTo(a.$1.length));

List<(String, TeamHomePlace)> _prefixEntries() => [
      ('anaheim', _usPlace('Anaheim', 'California', 'CA')),
      ('atlanta', _usPlace('Atlanta', 'Georgia', 'GA')),
      ('austin', _usPlace('Austin', 'Texas', 'TX')),
      ('baltimore', _usPlace('Baltimore', 'Maryland', 'MD')),
      ('boston', _usPlace('Boston', 'Massachusetts', 'MA')),
      ('buffalo', _usPlace('Buffalo', 'New York', 'NY')),
      ('charlotte', _usPlace('Charlotte', 'North Carolina', 'NC')),
      ('chicago', _usPlace('Chicago', 'Illinois', 'IL')),
      ('cincinnati', _usPlace('Cincinnati', 'Ohio', 'OH')),
      ('cleveland', _usPlace('Cleveland', 'Ohio', 'OH')),
      ('columbus', _usPlace('Columbus', 'Ohio', 'OH')),
      ('dallas', _usPlace('Dallas', 'Texas', 'TX')),
      ('denver', _usPlace('Denver', 'Colorado', 'CO')),
      ('detroit', _usPlace('Detroit', 'Michigan', 'MI')),
      ('houston', _usPlace('Houston', 'Texas', 'TX')),
      ('kansas city', _usPlace('Kansas City', 'Missouri', 'MO')),
      ('los angeles', _usPlace('Los Angeles', 'California', 'CA')),
      ('memphis', _usPlace('Memphis', 'Tennessee', 'TN')),
      ('miami', _usPlace('Miami', 'Florida', 'FL')),
      ('milwaukee', _usPlace('Milwaukee', 'Wisconsin', 'WI')),
      ('nashville', _usPlace('Nashville', 'Tennessee', 'TN')),
      ('new jersey', _usPlace('Newark', 'New Jersey', 'NJ')),
      ('new orleans', _usPlace('New Orleans', 'Louisiana', 'LA')),
      ('new york', _usPlace('New York', 'New York', 'NY')),
      ('oklahoma city', _usPlace('Oklahoma City', 'Oklahoma', 'OK')),
      ('orlando', _usPlace('Orlando', 'Florida', 'FL')),
      ('philadelphia', _usPlace('Philadelphia', 'Pennsylvania', 'PA')),
      ('phoenix', _usPlace('Phoenix', 'Arizona', 'AZ')),
      ('pittsburgh', _usPlace('Pittsburgh', 'Pennsylvania', 'PA')),
      ('portland', _usPlace('Portland', 'Oregon', 'OR')),
      ('sacramento', _usPlace('Sacramento', 'California', 'CA')),
      ('san antonio', _usPlace('San Antonio', 'Texas', 'TX')),
      ('san diego', _usPlace('San Diego', 'California', 'CA')),
      ('san francisco', _usPlace('San Francisco', 'California', 'CA')),
      ('san jose', _usPlace('San Jose', 'California', 'CA')),
      ('seattle', _usPlace('Seattle', 'Washington', 'WA')),
      ('st. louis', _usPlace('St. Louis', 'Missouri', 'MO')),
      ('washington', _usPlace('Washington', 'District of Columbia', 'DC')),
    ];
