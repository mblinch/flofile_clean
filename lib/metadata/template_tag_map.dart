import '../helpers.dart';
import '../services/iptc_template_apply_service.dart';

/// Builds the ExifTool-style tag map that template apply would write for a
/// full panel (replace semantics), so both writers can be fed the same map.
Map<String, String> templatePanelToTagMap(Map<String, String> panel) {
  final tags = <String, String>{};

  panel.forEach((key, value) {
    final v = value.trim();
    if (v.isEmpty) return;
    if (key.startsWith('Supp Cat ')) return;
    if (key == 'Keywords') return;
    if (key == 'Country Code') return;
    final preset = IptcTemplateApplyService.toPresetKey(key);
    // Parity-safe writes: avoid ExifTool alias stacks that duplicate IPTC
    // (bare By-lineTitle / AuthorsPosition both map into IPTC:By-lineTitle).
    if (preset == "Creator's Job Title" || preset == 'Job Title') {
      tags['IPTC:By-lineTitle'] = v;
      return;
    }
    if (preset == 'Stadium' || preset == 'Location') {
      tags['IPTC:Sub-location'] = v;
      tags['XMP-iptcCore:Location'] = v;
      return;
    }
    if (preset == 'Province/State') {
      tags['IPTC:Province-State'] = v;
      tags['XMP-photoshop:State'] = v;
      return;
    }
    if (preset == 'Country') {
      tags['IPTC:Country-PrimaryLocationName'] = v;
      tags['XMP-photoshop:Country'] = v;
      return;
    }
    if (preset == 'MEID') {
      tags['IPTC:OriginalTransmissionReference'] = v;
      return;
    }
    if (preset == 'Object Name' || preset == 'ObjectName') {
      tags['IPTC:ObjectName'] = v;
      tags['XMP:Title'] = v;
      return;
    }
    IptcTemplateApplyService.addExiftoolTagsForPresetKey(tags, preset, v);
  });

  final keywords = panel['Keywords']?.trim();
  if (keywords != null && keywords.isNotEmpty) {
    // Writer clears then sets from IPTC:Keywords / XMP-dc:Subject.
    tags['IPTC:Keywords'] = keywords;
    tags['Keywords'] = keywords;
    tags['XMP-dc:Subject'] = keywords;
    tags['XMP:Subject'] = keywords;
  }

  final country = panel['Country Code']?.trim();
  if (country != null && country.isNotEmpty) {
    final parts = dedupeMetadataListValues(
      country.split(RegExp(r'[,;/\s]+')),
    );
    final code = parts.isEmpty ? '' : parts.first;
    if (code.isNotEmpty) {
      tags['IPTC:Country-PrimaryLocationCode'] = code;
      tags['Country-PrimaryLocationCode'] = code;
      tags['XMP-iptcCore:CountryCode'] = code;
    }
  }

  final suppRaw = <String>[];
  for (var i = 1; i <= 3; i++) {
    final v = panel['Supp Cat $i']?.trim() ?? '';
    if (v.isNotEmpty) suppRaw.add(v);
  }
  // Slots alone — both writers expand SupplementalCategories1..3 into repeated
  // IPTC / XMP-photoshop entries (never one joined string).
  final supp = normalizeSupplementalCategories(suppRaw);
  for (var i = 0; i < supp.length && i < 3; i++) {
    tags['SupplementalCategories${i + 1}'] = supp[i];
  }

  return tags;
}

/// The ~20 Getty / FloFile template fields used in writer parity tests.
const Map<String, String> kTwentyFieldTemplateFixture = {
  'Creator': 'Mark Blinch',
  'Job Title': 'Contributor',
  'Description Writers': 'MB',
  'Copyright': '2026 Mark Blinch',
  'Credit': 'Getty Images',
  'Source': 'Getty Images North America',
  'MEID': '776465233',
  'Category': 'SPO',
  'Supp Cat 1': 'SPO',
  'Supp Cat 2': 'BBN',
  'Supp Cat 3': 'BBA',
  'Stadium': 'Rogers Centre',
  'City': 'Toronto',
  'Province/State': 'Ontario',
  'Country': 'Canada',
  'Country Code': 'CAN',
  'Headline': 'Blue Jays vs Yankees',
  'Keywords': 'Bo Bichette, Toronto Blue Jays',
  'Personality': 'Bo Bichette;Vladimir Guerrero Jr.',
  'Object Name': '776465233_MB_01_JAYS',
  'Special Instructions': 'FOR EDITORIAL USE ONLY',
  'Caption':
      'Bo Bichette #11 of the Toronto Blue Jays bats during the game against the New York Yankees at Rogers Centre.',
};
