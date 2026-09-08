import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/screens/caption_v2/data/caption_transfer_payload.dart';

void main() {
  test('round trips the canonical payload', () {
    const original = CaptionTransferPayload(
      caption: 'Caption text',
      personality: 'Player One;Player Two',
      headline: 'Headline',
      keywords: 'baseball;celebration',
    );

    final decoded = CaptionTransferPayload.decode(original.encode());

    expect(decoded?.caption, original.caption);
    expect(decoded?.personality, original.personality);
    expect(decoded?.headline, original.headline);
    expect(decoded?.keywords, original.keywords);
  });

  test('accepts V1 and current V2 clipboard keys', () {
    final v1 = CaptionTransferPayload.decode(
      '{"caption":"V1 caption","personality":"V1 player"}',
    );
    final v2 = CaptionTransferPayload.decode(
      '{"Caption":"V2 caption","Personality":"V2 player","Keywords":["one","two"]}',
    );

    expect(v1?.caption, 'V1 caption');
    expect(v1?.personality, 'V1 player');
    expect(v2?.caption, 'V2 caption');
    expect(v2?.personality, 'V2 player');
    expect(v2?.keywords, 'one;two');
  });

  test('accepts IPTC aliases and plain text', () {
    final iptc = CaptionTransferPayload.decode(
      '{"IPTC:Description":"IPTC caption","IPTC:Headline":"News"}',
    );
    final plain = CaptionTransferPayload.decode('A plain caption');

    expect(iptc?.caption, 'IPTC caption');
    expect(iptc?.headline, 'News');
    expect(plain?.caption, 'A plain caption');
  });

  test('rejects empty and JSON without a caption', () {
    expect(CaptionTransferPayload.decode('  '), isNull);
    expect(CaptionTransferPayload.decode('{"Personality":"Player"}'), isNull);
  });
}
