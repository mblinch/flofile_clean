import 'dart:convert';

import 'region_abbrev.dart';

/// Static game/session fields (same for every frame until edited).
class GameInfo {
  const GameInfo({
    this.gameDate,
    this.city = '',
    this.region = '',
    this.regionCode = '',
    this.country = '',
    this.countryCode = '',
    this.venue = '',
    this.photographerName = '',
    this.agencyName = '',
    this.iptcMetadata = const {},
  });

  final DateTime? gameDate;
  final String city;
  final String region;
  /// Optional explicit short region (e.g. IPTC abbrev); else derived from [region].
  final String regionCode;
  /// Full country name (e.g. IPTC Country / CountryPrimaryLocationName).
  final String country;
  /// ISO country code (e.g. IPTC CountryPrimaryLocationCode / CountryCode).
  final String countryCode;
  final String venue;
  final String photographerName;
  final String agencyName;
  /// IPTC/XMP keys (e.g. `DateTimeOriginal`, `CreateDate`) → raw string values from the file.
  final Map<String, String> iptcMetadata;

  GameInfo copyWith({
    DateTime? gameDate,
    bool clearGameDate = false,
    String? city,
    String? region,
    String? regionCode,
    String? country,
    String? countryCode,
    String? venue,
    String? photographerName,
    String? agencyName,
    Map<String, String>? iptcMetadata,
  }) =>
      GameInfo(
        gameDate: clearGameDate ? null : (gameDate ?? this.gameDate),
        city: city ?? this.city,
        region: region ?? this.region,
        regionCode: regionCode ?? this.regionCode,
        country: country ?? this.country,
        countryCode: countryCode ?? this.countryCode,
        venue: venue ?? this.venue,
        photographerName: photographerName ?? this.photographerName,
        agencyName: agencyName ?? this.agencyName,
        iptcMetadata: iptcMetadata ?? this.iptcMetadata,
      );

  Map<String, dynamic> toJson() => {
        if (gameDate != null) 'gameDate': gameDate!.toIso8601String(),
        'city': city,
        'region': region,
        'regionCode': regionCode,
        'country': country,
        'countryCode': countryCode,
        'venue': venue,
        'photographerName': photographerName,
        'agencyName': agencyName,
        if (iptcMetadata.isNotEmpty) 'iptcMetadata': iptcMetadata,
      };

  static GameInfo fromJson(Map<String, dynamic> json) {
    DateTime? gd;
    final raw = json['gameDate'];
    if (raw is String && raw.isNotEmpty) {
      gd = DateTime.tryParse(raw);
    }
    Map<String, String> meta = const {};
    final im = json['iptcMetadata'];
    if (im is Map) {
      meta = im.map((k, v) => MapEntry(k.toString(), v.toString()));
    }
    return GameInfo(
      gameDate: gd,
      city: json['city'] as String? ?? '',
      region: json['region'] as String? ?? '',
      regionCode: json['regionCode'] as String? ?? '',
      country: json['country'] as String? ?? '',
      countryCode: json['countryCode'] as String? ?? '',
      venue: json['venue'] as String? ?? '',
      photographerName: json['photographerName'] as String? ?? '',
      agencyName: json['agencyName'] as String? ?? '',
      iptcMetadata: meta,
    );
  }

  static GameInfo? tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return GameInfo.fromJson(json.decode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  String encode() => json.encode(toJson());

  static const List<String> _iptcRegionNameKeys = [
    'IPTC:ProvinceState',
    'ProvinceState',
    'Province-State',
    'XMP:State',
  ];

  static const List<String> _iptcCountryNameKeys = [
    'IPTC:CountryPrimaryLocationName',
    'CountryPrimaryLocationName',
    'Country',
    'XMP:Country',
  ];

  static const List<String> _iptcCountryCodeKeys = [
    'IPTC:CountryPrimaryLocationCode',
    'CountryPrimaryLocationCode',
    'CountryCode',
  ];

  String _firstIptcValue(List<String> keys) {
    for (final k in keys) {
      final v = iptcMetadata[k]?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return '';
  }

  /// Full country name: [country] if set, else first matching IPTC/XMP key in [iptcMetadata].
  String get resolvedCountryName {
    final c = country.trim();
    if (c.isNotEmpty) return c;
    return _firstIptcValue(_iptcCountryNameKeys);
  }

  /// ISO country code: [countryCode] if set, else first matching IPTC/XMP key in [iptcMetadata].
  String get resolvedCountryCode {
    final c = countryCode.trim();
    if (c.isNotEmpty) return c;
    return _firstIptcValue(_iptcCountryCodeKeys);
  }

  /// State / province full name: [region] if set, else IPTC-style keys in [iptcMetadata].
  String get resolvedRegionName {
    final r = region.trim();
    if (r.isNotEmpty) return r;
    return _firstIptcValue(_iptcRegionNameKeys);
  }

  /// Short region: explicit [regionCode], else abbreviation of [resolvedRegionName]
  /// (e.g. California → CA, Ontario → Ont).
  String get resolvedRegionShort {
    final c = regionCode.trim();
    if (c.isNotEmpty) return c;
    return abbreviateRegionName(resolvedRegionName);
  }

  /// One-line summary for collapsed header.
  String summaryLine() {
    final loc = [city, region].where((s) => s.trim().isNotEmpty).join(', ');
    final dateStr = gameDate != null
        ? '${gameDate!.year}-${gameDate!.month.toString().padLeft(2, '0')}-${gameDate!.day.toString().padLeft(2, '0')}'
        : '—';
    final v = venue.trim().isEmpty ? '—' : venue.trim();
    return '$dateStr · ${loc.isEmpty ? '—' : loc} · $v';
  }
}
