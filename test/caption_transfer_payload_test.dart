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
    expect(decoded?.photographerName, '');
  });

  test('keeps the destination photographer in a pasted caption', () {
    const source =
        'Maria Lopez #12 scores a goal. (Photo by John Smith/Getty Images)';

    expect(
      CaptionTransferPayload.captionForDestinationPhotographer(
        caption: source,
        sourcePhotographer: 'John Smith',
        destinationPhotographer: 'Jane Doe',
      ),
      'Maria Lopez #12 scores a goal. (Photo by Jane Doe/Getty Images)',
    );
  });

  test('replaces only the byline when the photographer is also in the play',
      () {
    const source =
        'John Smith scores on a header. (Photo by John Smith/Getty Images)';

    expect(
      CaptionTransferPayload.captionForDestinationPhotographer(
        caption: source,
        sourcePhotographer: 'John Smith',
        destinationPhotographer: 'Jane Doe',
      ),
      'John Smith scores on a header. (Photo by Jane Doe/Getty Images)',
    );
  });

  test('keeps caption-style caps and drops accents when the caption does', () {
    expect(
      CaptionTransferPayload.captionForDestinationPhotographer(
        caption: 'A save. (Photo by JOSE GARCIA/AP)',
        sourcePhotographer: 'José García',
        destinationPhotographer: 'André Müller',
        removeDiacritics: true,
      ),
      'A save. (Photo by ANDRE MULLER/AP)',
    );
  });

  test('leaves the copied name when the destination photo has none', () {
    const source = 'A save. (Photo by John Smith/AP)';
    expect(
      CaptionTransferPayload.captionForDestinationPhotographer(
        caption: source,
        sourcePhotographer: 'John Smith',
        destinationPhotographer: '  ',
      ),
      source,
    );
  });

  test('does not treat a shorter name as part of a longer word', () {
    expect(
      CaptionTransferPayload.captionForDestinationPhotographer(
        caption: 'Johnson waits on the bench. (Photo by John/AP)',
        sourcePhotographer: 'John',
        destinationPhotographer: 'Jane Doe',
      ),
      'Johnson waits on the bench. (Photo by Jane Doe/AP)',
    );
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
