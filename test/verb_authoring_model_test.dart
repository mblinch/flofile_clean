import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/caption_style/verb_authoring_model.dart';

void main() {
  test('phrase slots resolve from defaults and selections', () {
    const groups = [
      VerbModifierGroup(
        id: 'runners',
        name: 'Runners on',
        kind: VerbModifierKind.tokens,
        required: true,
        defaultOptionId: 'solo',
        options: [
          VerbModifierOption(id: 'solo', label: 'SOLO', value: 'solo'),
          VerbModifierOption(id: 'two', label: '2R', value: 'two-run'),
        ],
      ),
    ];
    const phrase = VerbPhraseTemplate([
      VerbPhraseText('hits a '),
      VerbPhraseSlot('runners'),
      VerbPhraseText(' home run'),
    ]);

    expect(phrase.resolve(groups, const {}), 'hits a solo home run');
    expect(
      phrase.resolve(groups, const {'runners': 'two'}),
      'hits a two-run home run',
    );
  });

  test('serialized phrase and groups round-trip', () {
    const original = VerbAuthoringData(
      phrase: VerbPhraseTemplate([
        VerbPhraseText('reacts '),
        VerbPhraseSlot('reaction'),
      ]),
      groups: [
        VerbModifierGroup(
          id: 'reaction',
          name: 'Reaction',
          kind: VerbModifierKind.words,
          required: false,
          options: [
            VerbModifierOption(
              id: 'celebrates',
              label: 'Celebrates',
              value: 'celebrates',
            ),
          ],
        ),
      ],
    );

    final fields = original.toRecordFields();
    final decoded = VerbAuthoringData.fromRecord(
      fields,
      verbLabel: 'Reaction',
      sport: 'baseball',
      fallbackPhrase: 'reacts',
    );

    expect(decoded.groups.single.kind, VerbModifierKind.words);
    expect(
      decoded.phrase.resolve(
        decoded.groups,
        const {'reaction': 'celebrates'},
      ),
      'reacts celebrates',
    );
  });

  test('empty modifier group invalidates publish data', () {
    const data = VerbAuthoringData(
      phrase: VerbPhraseTemplate([VerbPhraseSlot('empty')]),
      groups: [
        VerbModifierGroup(
          id: 'empty',
          name: 'Empty',
          kind: VerbModifierKind.words,
          required: false,
          options: [],
        ),
      ],
    );

    expect(data.isValid, isFalse);
  });

  test('Single seeds RBI and reaction modifier groups from legacy defaults', () {
    final data = VerbAuthoringData.fromRecord(
      const {},
      verbLabel: 'Single',
      sport: 'baseball',
      fallbackPhrase: 'single',
    );

    expect(data.groups.map((group) => group.id), containsAll(['rbi', 'reaction']));
    expect(
      data.phrase.resolve(data.groups, const {'rbi': '0'}),
      'hits a single',
    );
    expect(
      data.phrase.resolve(data.groups, const {'rbi': '2'}),
      contains('single'),
    );
  });
}
