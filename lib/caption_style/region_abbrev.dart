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

/// True when [raw] is a known US state/territory full name, postal code, or
/// AP-style abbreviation (e.g. Florida, FL, Fla.).
bool isKnownUsStateOrTerritory(String raw) {
  final k = normalizeRegionKey(raw);
  if (k.isEmpty) return false;
  if (_usStates.containsKey(k)) return true;
  if (_usStatesApStyle.containsKey(k)) return true;
  final upper = raw.trim().toUpperCase();
  if (upper.length == 2 && _usPostalCodes.contains(upper)) return true;
  for (final v in _usStatesApStyle.values) {
    if (normalizeRegionKey(v) == k) return true;
  }
  return false;
}

/// US cities that stand alone in AP datelines (no state).
bool isApStandaloneCity(String city) {
  final k = normalizeRegionKey(city);
  if (k.isEmpty) return false;
  return _apStandaloneCities.contains(k);
}

/// When AP region style is on, omit the state for [city] (standalone list).
bool shouldOmitApStyleState({required String city, String region = ''}) {
  if (!isApStandaloneCity(city)) return false;
  // Standalone list is US-only; if an explicit non-US region is present, keep it.
  final r = region.trim();
  if (r.isNotEmpty &&
      !isKnownUsStateOrTerritory(r) &&
      abbreviateUsStateApStyle(r).isEmpty) {
    return false;
  }
  return true;
}

/// US state full name, postal code, or AP abbrev → AP-style output.
///
/// Never-abbreviated states (Alaska, Ohio, Texas, …) return the full name.
/// Returns empty string when unknown / non-US.
String abbreviateUsStateApStyle(String raw) {
  if (raw.trim().isEmpty) return '';
  final k = normalizeRegionKey(raw);

  // Full name (or never-abbreviate canonical).
  final fromFull = _usStatesApStyle[k];
  if (fromFull != null) return fromFull;

  // Postal code (CA, NY, OH, DC).
  final upper = raw.trim().toUpperCase();
  if (upper.length == 2 && _usPostalCodes.contains(upper)) {
    for (final e in _usStates.entries) {
      if (e.value == upper) {
        return _usStatesApStyle[e.key] ?? e.key;
      }
    }
  }

  // Already an AP abbreviation (Fla., N.Y., W.Va.).
  for (final e in _usStatesApStyle.entries) {
    if (normalizeRegionKey(e.value) == k) return e.value;
  }

  return '';
}

/// Resolve AP state text from full name and/or postal/code fields.
///
/// Empty when [shouldOmitApStyleState] is true for [city], or when both
/// region inputs are empty.
String formatApStyleState({
  required String city,
  String region = '',
  String regionCode = '',
}) {
  if (shouldOmitApStyleState(city: city, region: region.isNotEmpty ? region : regionCode)) {
    return '';
  }
  for (final candidate in [region, regionCode]) {
    final ap = abbreviateUsStateApStyle(candidate);
    if (ap.isNotEmpty) return ap;
  }
  final fallback = region.trim().isNotEmpty ? region.trim() : regionCode.trim();
  return fallback;
}

// ─── Canadian Press (CP) province / city ───────────────────────────────────

/// CP Stylebook Canadian cities that stand alone (no province).
///
/// Edit this list to add cities (likely later: Saskatoon, St. John's,
/// Charlottetown, Whitehorse, Yellowknife).
const Set<String> kCpStandaloneCanadianCities = {
  'toronto',
  'montreal',
  'vancouver',
  'calgary',
  'edmonton',
  'ottawa',
  'winnipeg',
  'hamilton',
  'regina',
  'halifax',
  'quebec city',
  'victoria',
  'fredericton',
};

/// True when [city] is a CP standalone Canadian dateline city (no province).
bool isCpStandaloneCanadianCity(String city) {
  final k = normalizeRegionKey(city);
  if (k.isEmpty) return false;
  if (kCpStandaloneCanadianCities.contains(k)) return true;
  // Accented forms (Montréal, Québec City).
  final folded = k
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('ë', 'e')
      .replaceAll('à', 'a')
      .replaceAll('â', 'a')
      .replaceAll('ô', 'o')
      .replaceAll('ç', 'c')
      .replaceAll('ü', 'u');
  return kCpStandaloneCanadianCities.contains(folded);
}

/// When CP province style is on, omit the province for [city] (standalone list).
bool shouldOmitCpStyleProvince({required String city, String region = ''}) {
  if (!isCpStandaloneCanadianCity(city)) return false;
  // Standalone list is Canada-only; if an explicit non-Canadian region is
  // present, keep it.
  final r = region.trim();
  if (r.isNotEmpty && abbreviateCpStyleProvince(r).isEmpty) {
    return false;
  }
  return true;
}

/// Full name, postal code, or CP abbrev → CP Stylebook province abbreviation.
///
/// Never-abbreviated territories (Yukon, Nunavut) return the full name.
/// Returns empty string when unknown / non-Canadian.
String abbreviateCpStyleProvince(String raw) {
  if (raw.trim().isEmpty) return '';
  // Allow "Que." / "Que.," / "Ont" inputs to match the same keys.
  final stripped = raw.trim().replaceFirst(RegExp(r',+\s*$'), '');
  final k = normalizeRegionKey(stripped);

  final fromFull = _cpProvinces[k];
  if (fromFull != null) return fromFull;

  // Postal / ISO-ish codes (ON, QC, BC, NL, …).
  final upper = stripped.trim().toUpperCase();
  final fromPostal = _cpPostalToAbbrev[upper];
  if (fromPostal != null) return fromPostal;

  // Already a CP abbreviation (Que., B.C., Ont., Nfld.).
  for (final e in _cpProvinces.entries) {
    if (normalizeRegionKey(e.value.replaceFirst(RegExp(r',+\s*$'), '')) == k) {
      return e.value;
    }
  }

  return '';
}

/// Resolve CP province text from city + region fields.
///
/// Empty when [shouldOmitCpStyleProvince] is true, or when both region inputs
/// are empty / unrecognized.
String formatCpStyleProvince({
  required String city,
  String region = '',
  String regionCode = '',
}) {
  if (shouldOmitCpStyleProvince(
    city: city,
    region: region.isNotEmpty ? region : regionCode,
  )) {
    return '';
  }
  for (final candidate in [region, regionCode]) {
    final cp = abbreviateCpStyleProvince(candidate);
    if (cp.isNotEmpty) return cp;
  }
  final fallback = region.trim().isNotEmpty ? region.trim() : regionCode.trim();
  return fallback;
}

/// CP Stylebook province / territory abbreviations (full-name keys).
/// Trailing comma is part of the short form so copy continues cleanly
/// ("Brossard, Que., on Friday…").
const Map<String, String> _cpProvinces = {
  'alberta': 'Alta.,',
  'british columbia': 'B.C.,',
  'saskatchewan': 'Sask.,',
  'manitoba': 'Man.,',
  'ontario': 'Ont.,',
  'quebec': 'Que.,',
  'new brunswick': 'N.B.,',
  'nova scotia': 'N.S.,',
  'prince edward island': 'P.E.I.,',
  'newfoundland and labrador': 'Nfld.,',
  'newfoundland': 'Nfld.,',
  'labrador': 'Nfld.,',
  'northwest territories': 'N.W.T.,',
  // Never abbreviate (still take the trailing comma):
  'yukon': 'Yukon,',
  'nunavut': 'Nunavut,',
};

/// Canadian postal / short codes → CP Stylebook abbreviations.
const Map<String, String> _cpPostalToAbbrev = {
  'AB': 'Alta.,',
  'BC': 'B.C.,',
  'SK': 'Sask.,',
  'MB': 'Man.,',
  'ON': 'Ont.,',
  'QC': 'Que.,',
  'NB': 'N.B.,',
  'NS': 'N.S.,',
  'PE': 'P.E.I.,',
  'PEI': 'P.E.I.,',
  'NL': 'Nfld.,',
  'NF': 'Nfld.,',
  'NT': 'N.W.T.,',
  'NWT': 'N.W.T.,',
  'YT': 'Yukon,',
  'YK': 'Yukon,',
  'NU': 'Nunavut,',
};

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

final Set<String> _usPostalCodes = {
  ..._usStates.values,
  'DC',
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

/// AP Stylebook state abbreviations. Never-abbreviated states map to full name.
const Map<String, String> _usStatesApStyle = {
  'alabama': 'Ala.',
  'alaska': 'Alaska',
  'arizona': 'Ariz.',
  'arkansas': 'Ark.',
  'california': 'Calif.',
  'colorado': 'Colo.',
  'connecticut': 'Conn.',
  'delaware': 'Del.',
  'district of columbia': 'D.C.',
  'florida': 'Fla.',
  'georgia': 'Ga.',
  'hawaii': 'Hawaii',
  'idaho': 'Idaho',
  'illinois': 'Ill.',
  'indiana': 'Ind.',
  'iowa': 'Iowa',
  'kansas': 'Kan.',
  'kentucky': 'Ky.',
  'louisiana': 'La.',
  'maine': 'Maine',
  'maryland': 'Md.',
  'massachusetts': 'Mass.',
  'michigan': 'Mich.',
  'minnesota': 'Minn.',
  'mississippi': 'Miss.',
  'missouri': 'Mo.',
  'montana': 'Mont.',
  'nebraska': 'Neb.',
  'nevada': 'Nev.',
  'new hampshire': 'N.H.',
  'new jersey': 'N.J.',
  'new mexico': 'N.M.',
  'new york': 'N.Y.',
  'north carolina': 'N.C.',
  'north dakota': 'N.D.',
  'ohio': 'Ohio',
  'oklahoma': 'Okla.',
  'oregon': 'Ore.',
  'pennsylvania': 'Pa.',
  'rhode island': 'R.I.',
  'south carolina': 'S.C.',
  'south dakota': 'S.D.',
  'tennessee': 'Tenn.',
  'texas': 'Texas',
  'utah': 'Utah',
  'vermont': 'Vt.',
  'virginia': 'Va.',
  'washington': 'Wash.',
  'west virginia': 'W.Va.',
  'wisconsin': 'Wis.',
  'wyoming': 'Wyo.',
};

/// Exact AP standalone dateline cities (no state).
const Set<String> _apStandaloneCities = {
  'atlanta',
  'baltimore',
  'boston',
  'chicago',
  'cincinnati',
  'cleveland',
  'dallas',
  'denver',
  'detroit',
  'honolulu',
  'houston',
  'indianapolis',
  'las vegas',
  'los angeles',
  'miami',
  'milwaukee',
  'minneapolis',
  'new orleans',
  'new york',
  'oklahoma city',
  'philadelphia',
  'phoenix',
  'pittsburgh',
  'st. louis',
  'salt lake city',
  'san antonio',
  'san diego',
  'san francisco',
  'seattle',
  'washington',
};
