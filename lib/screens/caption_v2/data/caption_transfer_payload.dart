import 'dart:convert';

class CaptionTransferPayload {
  const CaptionTransferPayload({
    required this.caption,
    this.personality = '',
    this.headline = '',
    this.keywords = '',
  });

  static const int currentVersion = 1;

  final String caption;
  final String personality;
  final String headline;
  final String keywords;

  Map<String, dynamic> toJson() {
    return {
      'version': currentVersion,
      'caption': caption,
      'personality': personality,
      'headline': headline,
      'keywords': keywords,
    };
  }

  String encode() => jsonEncode(toJson());

  static CaptionTransferPayload? decode(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;

    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      return CaptionTransferPayload(caption: raw);
    }
    if (decoded is! Map) {
      return CaptionTransferPayload(caption: raw);
    }
    final map = decoded;

    String value(List<String> keys) {
      for (final key in keys) {
        final candidate = map[key];
        if (candidate is String) return candidate;
        if (candidate is List) {
          return candidate.map((item) => item.toString()).join(';');
        }
      }
      return '';
    }

    final caption = value(const [
      'caption',
      'Caption',
      'IPTC:Description',
      'Description',
      'Caption-Abstract',
      'IPTC:Caption-Abstract',
      'XMP:Description',
      'ImageDescription',
    ]);
    if (caption.isEmpty) return null;

    return CaptionTransferPayload(
      caption: caption,
      personality: value(const [
        'personality',
        'Personality',
        'XMP-getty:Personality',
      ]),
      headline: value(const ['headline', 'Headline', 'IPTC:Headline']),
      keywords: value(const [
        'keywords',
        'Keywords',
        'IPTC:Keywords',
        'XMP:Subject',
      ]),
    );
  }
}
