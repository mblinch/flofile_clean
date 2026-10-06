/// Title-cases a verb display name: major words capitalized, short glue words
/// left lowercase (unless first or last).
///
/// Examples: `goes to the net` → `Goes to the Net`,
/// `celebrates a goal` → `Celebrates a Goal`.
String titleCaseVerbName(String input) {
  final trimmed = input.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (trimmed.isEmpty) return '';

  final words = trimmed.split(' ');
  final last = words.length - 1;
  return [
    for (var i = 0; i < words.length; i++)
      _titleCaseVerbWord(
        words[i],
        capitalize: i == 0 || i == last || !_verbNameSmallWords.contains(
          words[i].toLowerCase(),
        ),
      ),
  ].join(' ');
}

const _verbNameSmallWords = <String>{
  'a',
  'an',
  'the',
  'and',
  'or',
  'but',
  'for',
  'nor',
  'on',
  'at',
  'to',
  'from',
  'by',
  'of',
  'in',
  'with',
  'as',
  'vs',
  'via',
};

String _titleCaseVerbWord(String word, {required bool capitalize}) {
  if (word.isEmpty) return word;
  // Keep hyphenated segments consistent: "non-game" → "Non-Game" when capped.
  if (word.contains('-')) {
    return word
        .split('-')
        .map((part) => _titleCaseVerbWord(part, capitalize: capitalize))
        .join('-');
  }
  final lower = word.toLowerCase();
  if (!capitalize) return lower;
  if (lower.length == 1) return lower.toUpperCase();
  return '${lower[0].toUpperCase()}${lower.substring(1)}';
}
