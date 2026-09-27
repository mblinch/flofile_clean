import 'verb_caption_wording.dart';
import 'verb_sub_options.dart';

enum VerbModifierKind {
  tokens,
  words;

  static VerbModifierKind fromJson(Object? raw) =>
      raw?.toString() == 'tokens' ? tokens : words;
}

class VerbModifierOption {
  const VerbModifierOption({
    required this.id,
    required this.label,
    required this.value,
  });

  final String id;
  final String label;
  final String value;

  factory VerbModifierOption.fromJson(Object? raw) {
    final map = raw is Map ? Map<String, dynamic>.from(raw) : const {};
    final label = (map['label'] ?? map['value'] ?? '').toString().trim();
    return VerbModifierOption(
      id: (map['id'] ?? label.toLowerCase().replaceAll(' ', '_')).toString(),
      label: label,
      value: (map['value'] ?? label).toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'value': value,
      };
}

class VerbModifierGroup {
  const VerbModifierGroup({
    required this.id,
    required this.name,
    required this.kind,
    required this.required,
    required this.options,
    this.defaultOptionId,
  });

  final String id;
  final String name;
  final VerbModifierKind kind;
  final bool required;
  final List<VerbModifierOption> options;
  final String? defaultOptionId;

  bool get isValid =>
      id.trim().isNotEmpty && name.trim().isNotEmpty && options.isNotEmpty;

  factory VerbModifierGroup.fromJson(Object? raw) {
    final map = raw is Map ? Map<String, dynamic>.from(raw) : const {};
    final name = (map['name'] ?? '').toString().trim();
    return VerbModifierGroup(
      id: (map['id'] ?? name.toLowerCase().replaceAll(' ', '_')).toString(),
      name: name,
      kind: VerbModifierKind.fromJson(map['kind']),
      required: map['required'] == true,
      defaultOptionId: map['defaultOptionId']?.toString(),
      options: (map['options'] is List)
          ? (map['options'] as List)
              .map(VerbModifierOption.fromJson)
              .where((option) => option.label.isNotEmpty)
              .toList()
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'required': required,
        if (defaultOptionId != null) 'defaultOptionId': defaultOptionId,
        'options': options.map((option) => option.toJson()).toList(),
      };

  VerbModifierGroup copyWith({
    String? id,
    String? name,
    VerbModifierKind? kind,
    bool? required,
    List<VerbModifierOption>? options,
    String? defaultOptionId,
    bool clearDefault = false,
  }) {
    return VerbModifierGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      required: required ?? this.required,
      options: options ?? this.options,
      defaultOptionId:
          clearDefault ? null : (defaultOptionId ?? this.defaultOptionId),
    );
  }
}

abstract class VerbPhrasePart {
  const VerbPhrasePart();

  factory VerbPhrasePart.fromJson(Object? raw) {
    final map = raw is Map ? Map<String, dynamic>.from(raw) : const {};
    if (map['type'] == 'slot') {
      return VerbPhraseSlot((map['groupId'] ?? '').toString());
    }
    return VerbPhraseText((map['text'] ?? '').toString());
  }

  Map<String, dynamic> toJson();
}

class VerbPhraseText extends VerbPhrasePart {
  const VerbPhraseText(this.text);

  final String text;

  @override
  Map<String, dynamic> toJson() => {'type': 'text', 'text': text};
}

class VerbPhraseSlot extends VerbPhrasePart {
  const VerbPhraseSlot(this.groupId);

  final String groupId;

  @override
  Map<String, dynamic> toJson() => {'type': 'slot', 'groupId': groupId};
}

class VerbPhraseTemplate {
  const VerbPhraseTemplate(this.parts);

  final List<VerbPhrasePart> parts;

  factory VerbPhraseTemplate.fromJson(
    Object? raw, {
    required String fallbackPhrase,
  }) {
    if (raw is List) {
      final parsed = raw.map(VerbPhrasePart.fromJson).toList();
      if (parsed.isNotEmpty) return VerbPhraseTemplate(parsed);
    }
    return VerbPhraseTemplate([VerbPhraseText(fallbackPhrase)]);
  }

  String resolve(
    List<VerbModifierGroup> groups,
    Map<String, String?> selections,
  ) {
    final byId = {for (final group in groups) group.id: group};
    final buffer = StringBuffer();
    for (final part in parts) {
      if (part is VerbPhraseText) {
        buffer.write(part.text);
      } else if (part is VerbPhraseSlot) {
        final group = byId[part.groupId];
        if (group == null) continue;
        final selectedId = selections[group.id] ?? group.defaultOptionId;
        final option =
            group.options.where((item) => item.id == selectedId).firstOrNull;
        if (option != null) buffer.write(option.value);
      }
    }
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  List<Map<String, dynamic>> toJson() =>
      parts.map((part) => part.toJson()).toList();

  bool references(String groupId) => parts.any(
        (part) => part is VerbPhraseSlot && part.groupId == groupId,
      );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}

class VerbAuthoringData {
  const VerbAuthoringData({
    required this.phrase,
    required this.groups,
  });

  final VerbPhraseTemplate phrase;
  final List<VerbModifierGroup> groups;

  bool get isValid =>
      groups.every((group) => group.isValid) &&
      groups
          .where((group) => phrase.references(group.id))
          .every((group) => group.options.isNotEmpty);

  factory VerbAuthoringData.fromRecord(
    Map<String, dynamic> record, {
    required String verbLabel,
    required String sport,
    required String fallbackPhrase,
    VerbSubOptions? subOptions,
  }) {
    final rawGroups = record['modifierGroups'];
    if (rawGroups is List) {
      return VerbAuthoringData(
        phrase: VerbPhraseTemplate.fromJson(
          record['phraseTemplate'],
          fallbackPhrase: fallbackPhrase,
        ),
        groups: rawGroups.map(VerbModifierGroup.fromJson).toList(),
      );
    }

    final legacy =
        subOptions ?? VerbSubOptions.defaultsFor(verbLabel, sport: sport);
    return legacyAuthoringFor(
      verbLabel: verbLabel,
      sport: sport,
      fallbackPhrase: fallbackPhrase,
      subOptions: legacy,
    );
  }

  /// Seeds phrase slots + groups from legacy [VerbSubOptions] for hit /
  /// celebration verbs. Other verbs get a plain text phrase.
  static VerbAuthoringData legacyAuthoringFor({
    required String verbLabel,
    required String sport,
    required String fallbackPhrase,
    required VerbSubOptions subOptions,
  }) {
    final reactionOptions = subOptions.reactionPhraseList
        .map(
          (label) => VerbModifierOption(
            id: label.toLowerCase().replaceAll(' ', '_'),
            label: label.isEmpty
                ? label
                : label[0].toUpperCase() + label.substring(1),
            value: label,
          ),
        )
        .toList();

    if (verbLabel == 'Home Run') {
      return VerbAuthoringData(
        phrase: const VerbPhraseTemplate([
          VerbPhraseText('hits a '),
          VerbPhraseSlot('runners_on'),
          VerbPhraseText(' home run'),
          VerbPhraseText(' '),
          VerbPhraseSlot('reaction'),
        ]),
        groups: [
          const VerbModifierGroup(
            id: 'runners_on',
            name: 'Runners on',
            kind: VerbModifierKind.tokens,
            required: true,
            defaultOptionId: 'solo',
            options: [
              VerbModifierOption(id: 'solo', label: 'SOLO', value: 'solo'),
              VerbModifierOption(id: '2r', label: '2R', value: 'two-run'),
              VerbModifierOption(id: '3r', label: '3R', value: 'three-run'),
              VerbModifierOption(
                id: 'gs',
                label: 'GS',
                value: 'grand slam',
              ),
            ],
          ),
          VerbModifierGroup(
            id: 'reaction',
            name: 'Reaction',
            kind: VerbModifierKind.words,
            required: false,
            options: reactionOptions,
          ),
        ],
      );
    }

    final isHit = VerbSubOptions.isBaseballSport(sport) &&
        VerbSubOptions.isHitVerb(verbLabel);
    if (isHit) {
      final noun = _hitNoun(verbLabel);
      final rbiOptions = _rbiOptionsFor(subOptions);
      final after = subOptions.rbiPlacesAfterHit;
      final phrase = after
          ? VerbPhraseTemplate([
              VerbPhraseText('hits a $noun'),
              VerbPhraseText(' '),
              const VerbPhraseSlot('rbi'),
              VerbPhraseText(' '),
              const VerbPhraseSlot('reaction'),
            ])
          : VerbPhraseTemplate([
              const VerbPhraseText('hits a '),
              const VerbPhraseSlot('rbi'),
              VerbPhraseText(noun),
              const VerbPhraseText(' '),
              const VerbPhraseSlot('reaction'),
            ]);
      return VerbAuthoringData(
        phrase: phrase,
        groups: [
          VerbModifierGroup(
            id: 'rbi',
            name: 'RBI',
            kind: VerbModifierKind.tokens,
            required: false,
            defaultOptionId: '0',
            options: rbiOptions,
          ),
          VerbModifierGroup(
            id: 'reaction',
            name: 'Reaction',
            kind: VerbModifierKind.words,
            required: false,
            options: reactionOptions,
          ),
        ],
      );
    }

    if (VerbSubOptions.isCelebrationVerb(verbLabel) ||
        subOptions.celebrationEnabled) {
      final base = fallbackPhrase.trim().isEmpty
          ? VerbCaptionWording.defaultWording(verbLabel)
          : fallbackPhrase.trim();
      return VerbAuthoringData(
        phrase: VerbPhraseTemplate([
          VerbPhraseText(base),
          const VerbPhraseText(' '),
          const VerbPhraseSlot('reaction'),
        ]),
        groups: [
          VerbModifierGroup(
            id: 'reaction',
            name: 'Reaction',
            kind: VerbModifierKind.words,
            required: false,
            options: reactionOptions,
          ),
        ],
      );
    }

    return VerbAuthoringData(
      phrase: VerbPhraseTemplate.fromJson(
        null,
        fallbackPhrase: fallbackPhrase,
      ),
      groups: const [],
    );
  }

  static String _hitNoun(String verbLabel) {
    switch (verbLabel) {
      case 'Home Run':
        return 'home run';
      case 'Sacrifice Fly':
        return 'sacrifice fly';
      case 'Hit by Pitch':
        return 'hit by pitch';
      case 'Bunts':
        return 'bunt';
      default:
        return verbLabel.toLowerCase();
    }
  }

  static List<VerbModifierOption> _rbiOptionsFor(VerbSubOptions subOptions) {
    String valueFor(int count) {
      if (count < 1) return '';
      final label = subOptions.rbiCountLabel(count);
      if (subOptions.rbiPlacesAfterHit) return label;
      return '$label ';
    }

    return [
      VerbModifierOption(id: '0', label: '0', value: valueFor(0)),
      VerbModifierOption(id: '1', label: '1', value: valueFor(1)),
      VerbModifierOption(id: '2', label: '2', value: valueFor(2)),
      VerbModifierOption(id: '3', label: '3', value: valueFor(3)),
      VerbModifierOption(id: '4', label: '4', value: valueFor(4)),
    ];
  }

  Map<String, dynamic> toRecordFields() => {
        'phraseTemplate': phrase.toJson(),
        'modifierGroups': groups.map((group) => group.toJson()).toList(),
      };
}
