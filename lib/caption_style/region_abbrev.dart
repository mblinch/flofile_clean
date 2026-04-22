/// Normalizes a province / state string for lookup (trim, lower case, strip trailing dots).
String normalizeRegionKey(String raw) {
  var s = raw.trim().toLowerCase();
  while (s.endsWith('.')) {
    s = s.substring(0, s.length - 1).trim().toLowerCase();
  }
  return s.replaceAll(RegExp(r'\s+'), ' ');
}

/// US state / territory and Canadian province / territory → common short caption form
/// (e.g. California → CA, Ontario → Ont). Returns empty when unknown.
String abbreviateRegionName(String fullName) {
  if (fullName.trim().isEmpty) return '';
  final k = normalizeRegionKey(fullName);
  return _usStates[k] ?? _canada[k] ?? '';
}

const Map<String, String> _usStates = {
  'alabama': 'AL',
  'alaska': 'AK',
  'arizona': 'AZ',
  'arkansas': 'AR',
  'california': 'CA',
  'colorado': 'CO',
  'connecticut': 'CT',
  'delaware': 'DE',
  'florida': 'FL',
  'georgia': 'GA',
  'hawaii': 'HI',
  'idaho': 'ID',
  'illinois': 'IL',
  'indiana': 'IN',
  'iowa': 'IA',
  'kansas': 'KS',
  'kentucky': 'KY',
  'louisiana': 'LA',
  'maine': 'ME',
  'maryland': 'MD',
  'massachusetts': 'MA',
  'michigan': 'MI',
  'minnesota': 'MN',
  'mississippi': 'MS',
  'missouri': 'MO',
  'montana': 'MT',
  'nebraska': 'NE',
  'nevada': 'NV',
  'new hampshire': 'NH',
  'new jersey': 'NJ',
  'new mexico': 'NM',
  'new york': 'NY',
  'north carolina': 'NC',
  'north dakota': 'ND',
  'ohio': 'OH',
  'oklahoma': 'OK',
  'oregon': 'OR',
  'pennsylvania': 'PA',
  'rhode island': 'RI',
  'south carolina': 'SC',
  'south dakota': 'SD',
  'tennessee': 'TN',
  'texas': 'TX',
  'utah': 'UT',
  'vermont': 'VT',
  'virginia': 'VA',
  'washington': 'WA',
  'west virginia': 'WV',
  'wisconsin': 'WI',
  'wyoming': 'WY',
  'district of columbia': 'DC',
};

/// Canadian short forms: Ontario → Ont per common wire style; others mostly 2-letter.
const Map<String, String> _canada = {
  'alberta': 'AB',
  'british columbia': 'BC',
  'manitoba': 'MB',
  'new brunswick': 'NB',
  'newfoundland and labrador': 'NL',
  'newfoundland': 'NL',
  'labrador': 'NL',
  'nova scotia': 'NS',
  'ontario': 'Ont',
  'prince edward island': 'PE',
  'quebec': 'QC',
  'saskatchewan': 'SK',
  'northwest territories': 'NT',
  'nunavut': 'NU',
  'yukon': 'YT',
};
