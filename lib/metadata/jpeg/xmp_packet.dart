import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

/// Minimal XMP packet read/write for the tags FloFile writes.
///
/// Personality is a single `rdf:li` with the semicolon-joined string (matches
/// ExifTool / Photo Mechanic). Keywords go in `dc:subject` as one li each.
class XmpPacket {
  XmpPacket({Map<String, dynamic>? fields})
      : fields = Map<String, dynamic>.from(fields ?? const {});

  /// Scalar string fields and list fields (`subject`, `supplementalCategories`).
  final Map<String, dynamic> fields;

  static const nsRdf = 'http://www.w3.org/1999/02/22-rdf-syntax-ns#';
  static const nsDc = 'http://purl.org/dc/elements/1.1/';
  static const nsPhotoshop = 'http://ns.adobe.com/photoshop/1.0/';
  static const nsIptcCore = 'http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/';
  static const nsGetty = 'http://xmp.gettyimages.com/gift/1.0/';
  static const nsX = 'adobe:ns:meta/';

  static XmpPacket parse(Uint8List xmlBytes) {
    final text = utf8.decode(xmlBytes, allowMalformed: true);
    final doc = XmlDocument.parse(text);
    final fields = <String, dynamic>{};

    String? textOf(XmlElement? el) {
      if (el == null) return null;
      final li = el.findAllElements('li', namespace: nsRdf).toList();
      if (li.isNotEmpty) {
        return li.map((e) => e.innerText).join(';');
      }
      return el.innerText.trim().isEmpty ? null : el.innerText;
    }

    List<String> listOf(XmlElement? el) {
      if (el == null) return const [];
      return el
          .findAllElements('li', namespace: nsRdf)
          .map((e) => e.innerText)
          .where((s) => s.trim().isNotEmpty)
          .toList();
    }

    for (final desc in doc.findAllElements('Description', namespace: nsRdf)) {
      void takeScalar(String local, String ns, String key) {
        final el = desc.getElement(local, namespace: ns);
        final v = textOf(el);
        if (v != null) fields[key] = v;
      }

      takeScalar('description', nsDc, 'description');
      takeScalar('title', nsDc, 'title');
      takeScalar('rights', nsDc, 'rights');
      takeScalar('Headline', nsPhotoshop, 'headline');
      takeScalar('CaptionWriter', nsPhotoshop, 'captionWriter');
      takeScalar('Instructions', nsPhotoshop, 'instructions');
      takeScalar('Credit', nsPhotoshop, 'credit');
      takeScalar('Source', nsPhotoshop, 'source');
      takeScalar('City', nsPhotoshop, 'city');
      takeScalar('State', nsPhotoshop, 'state');
      takeScalar('Country', nsPhotoshop, 'country');
      takeScalar('CountryCode', nsIptcCore, 'countryCode');
      takeScalar('Location', nsIptcCore, 'location');

      final creator = desc.getElement('creator', namespace: nsDc);
      final creators = listOf(creator);
      if (creators.isNotEmpty) fields['creator'] = creators;

      final subject = desc.getElement('subject', namespace: nsDc);
      final subjects = listOf(subject);
      if (subjects.isNotEmpty) fields['subject'] = subjects;

      final supp = desc.getElement('SupplementalCategories', namespace: nsPhotoshop);
      final supps = listOf(supp);
      if (supps.isNotEmpty) fields['supplementalCategories'] = supps;

      final personality =
          desc.getElement('Personality', namespace: nsGetty);
      if (personality != null) {
        final lis = listOf(personality);
        if (lis.isNotEmpty) {
          // FloFile / ExifTool store one li with semicolon-joined names.
          fields['personality'] = lis.length == 1 ? lis.first : lis.join(';');
        } else {
          final t = personality.innerText.trim();
          if (t.isNotEmpty) fields['personality'] = t;
        }
      }
    }
    return XmpPacket(fields: fields);
  }

  void setScalar(String key, String? value) {
    if (value == null || value.isEmpty) {
      fields.remove(key);
    } else {
      fields[key] = value;
    }
  }

  void setList(String key, List<String>? values) {
    if (values == null || values.isEmpty) {
      fields.remove(key);
    } else {
      fields[key] = List<String>.from(values);
    }
  }

  /// Encodes a standalone XMP packet (no padding required for correctness).
  Uint8List encode() {
    final buf = StringBuffer();
    buf.writeln("<?xpacket begin='\uFEFF' id='W5M0MpCehiHzreSzNTczkc9d'?>");
    buf.writeln("<x:xmpmeta xmlns:x='$nsX'>");
    buf.writeln("<rdf:RDF xmlns:rdf='$nsRdf'>");

    void desc(String xmlnsAttrs, void Function(StringBuffer) body) {
      buf.writeln("<rdf:Description rdf:about=''");
      buf.writeln(' $xmlnsAttrs>');
      body(buf);
      buf.writeln('</rdf:Description>');
    }

    void bag(StringBuffer b, String nsPrefix, String name, List<String> items) {
      b.writeln('<$nsPrefix:$name>');
      b.writeln('<rdf:Bag>');
      for (final item in items) {
        b.writeln('<rdf:li>${_xmlEscape(item)}</rdf:li>');
      }
      b.writeln('</rdf:Bag>');
      b.writeln('</$nsPrefix:$name>');
    }

    void seq(StringBuffer b, String nsPrefix, String name, List<String> items) {
      b.writeln('<$nsPrefix:$name>');
      b.writeln('<rdf:Seq>');
      for (final item in items) {
        b.writeln('<rdf:li>${_xmlEscape(item)}</rdf:li>');
      }
      b.writeln('</rdf:Seq>');
      b.writeln('</$nsPrefix:$name>');
    }

    void alt(StringBuffer b, String nsPrefix, String name, String value) {
      b.writeln('<$nsPrefix:$name>');
      b.writeln('<rdf:Alt>');
      b.writeln('<rdf:li xml:lang="x-default">${_xmlEscape(value)}</rdf:li>');
      b.writeln('</rdf:Alt>');
      b.writeln('</$nsPrefix:$name>');
    }

    final personality = fields['personality'] as String?;
    if (personality != null && personality.isNotEmpty) {
      desc("xmlns:GettyImagesGIFT='$nsGetty'", (b) {
        bag(b, 'GettyImagesGIFT', 'Personality', [personality]);
      });
    }

    final hasDc = fields.containsKey('description') ||
        fields.containsKey('creator') ||
        fields.containsKey('subject') ||
        fields.containsKey('rights') ||
        fields.containsKey('title');
    if (hasDc) {
      desc("xmlns:dc='$nsDc'", (b) {
        final descText = fields['description'] as String?;
        if (descText != null) alt(b, 'dc', 'description', descText);
        final title = fields['title'] as String?;
        if (title != null) alt(b, 'dc', 'title', title);
        final rights = fields['rights'] as String?;
        if (rights != null) alt(b, 'dc', 'rights', rights);
        final creators = fields['creator'];
        if (creators is List && creators.isNotEmpty) {
          seq(b, 'dc', 'creator', creators.cast<String>());
        } else if (creators is String && creators.isNotEmpty) {
          seq(b, 'dc', 'creator', [creators]);
        }
        final subjects = fields['subject'];
        if (subjects is List && subjects.isNotEmpty) {
          bag(b, 'dc', 'subject', subjects.cast<String>());
        }
      });
    }

    final hasPs = [
      'headline',
      'captionWriter',
      'instructions',
      'credit',
      'source',
      'city',
      'state',
      'country',
      'supplementalCategories',
    ].any(fields.containsKey);
    if (hasPs) {
      desc("xmlns:photoshop='$nsPhotoshop'", (b) {
        void s(String local, String key) {
          final v = fields[key] as String?;
          if (v != null) {
            b.writeln(
                '<photoshop:$local>${_xmlEscape(v)}</photoshop:$local>');
          }
        }

        s('Headline', 'headline');
        s('CaptionWriter', 'captionWriter');
        s('Instructions', 'instructions');
        s('Credit', 'credit');
        s('Source', 'source');
        s('City', 'city');
        s('State', 'state');
        s('Country', 'country');
        final supp = fields['supplementalCategories'];
        if (supp is List && supp.isNotEmpty) {
          bag(b, 'photoshop', 'SupplementalCategories', supp.cast<String>());
        }
      });
    }

    final hasIptcCore =
        fields.containsKey('countryCode') || fields.containsKey('location');
    if (hasIptcCore) {
      desc("xmlns:Iptc4xmpCore='$nsIptcCore'", (b) {
        final cc = fields['countryCode'] as String?;
        if (cc != null) {
          b.writeln(
              '<Iptc4xmpCore:CountryCode>${_xmlEscape(cc)}</Iptc4xmpCore:CountryCode>');
        }
        final loc = fields['location'] as String?;
        if (loc != null) {
          b.writeln(
              '<Iptc4xmpCore:Location>${_xmlEscape(loc)}</Iptc4xmpCore:Location>');
        }
      });
    }

    buf.writeln('</rdf:RDF>');
    buf.writeln('</x:xmpmeta>');
    buf.write("<?xpacket end='w'?>");
    return Uint8List.fromList(utf8.encode(buf.toString()));
  }

  static String _xmlEscape(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
