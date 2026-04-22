/// Latin diacritic folding for wire-style captions (player names, keywords, etc.).
class CaptionTextNormalize {
  CaptionTextNormalize._();

  static const Map<String, String> _replacements = {
    'á': 'a',
    'à': 'a',
    'ä': 'a',
    'â': 'a',
    'ã': 'a',
    'å': 'a',
    'Á': 'A',
    'À': 'A',
    'Ä': 'A',
    'Â': 'A',
    'Ã': 'A',
    'Å': 'A',
    'é': 'e',
    'è': 'e',
    'ë': 'e',
    'ê': 'e',
    'É': 'E',
    'È': 'E',
    'Ë': 'E',
    'Ê': 'E',
    'í': 'i',
    'ì': 'i',
    'ï': 'i',
    'î': 'i',
    'Í': 'I',
    'Ì': 'I',
    'Ï': 'I',
    'Î': 'I',
    'ó': 'o',
    'ò': 'o',
    'ö': 'o',
    'ô': 'o',
    'õ': 'o',
    'ø': 'o',
    'ő': 'o',
    'Ő': 'O',
    'Ó': 'O',
    'Ò': 'O',
    'Ö': 'O',
    'Ô': 'O',
    'Õ': 'O',
    'Ø': 'O',
    'ú': 'u',
    'ù': 'u',
    'ü': 'u',
    'û': 'u',
    'ű': 'u',
    'Ű': 'U',
    'Ú': 'U',
    'Ù': 'U',
    'Ü': 'U',
    'Û': 'U',
    'ñ': 'n',
    'Ñ': 'N',
    'ç': 'c',
    'Ç': 'C',
    'ý': 'y',
    'ÿ': 'y',
    'Ý': 'Y',
    'ß': 'ss',
    'æ': 'ae',
    'Æ': 'AE',
    'œ': 'oe',
    'Œ': 'OE',
  };

  /// Returns [text] with common Latin accented letters replaced by ASCII pairs.
  static String stripDiacritics(String text) {
    if (text.isEmpty) return text;
    var result = text;
    _replacements.forEach((from, to) {
      result = result.replaceAll(from, to);
    });
    return result;
  }
}
