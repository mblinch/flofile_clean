import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/services/iptc_template_import_service.dart';

void main() {
  group('parseGettyIimText', () {
    const sample = '''
2:15:1:S
2:20:3:BBA
2:20:3:SPO
2:20:3:BBO
2:20:3:BBN
2:40:169:No more than 7 images from any single MLB game.
2:55:8:20260527
2:80:11:Mark Blinch
2:85:8:Stringer
2:90:7:Toronto
2:92:13:Rogers Centre
2:95:2:ON
2:100:3:CAN
2:101:6:Canada
2:103:9:776445455
2:105:33:Miami Marlins v Toronto Blue Jays
2:110:12:Getty Images
2:115:26:Getty Images North America
2:116:17:2026 Getty Images
2:120:137:TORONTO, CANADA - MAY 27: <<enter caption here>>
2:1200:2:No
2:1210:2:No
''';

    test('maps standard IPTC-IIM datasets to panel keys', () {
      final result = IptcTemplateImportService.parseGettyIimText(sample);
      final v = result.values;

      expect(v['Category'], 'S');
      expect(v['Supp Cat 1'], 'BBA');
      expect(v['Supp Cat 2'], 'SPO');
      expect(v['Supp Cat 3'], 'BBO');
      expect(v['Creator'], 'Mark Blinch');
      expect(v['Job Title'], 'Stringer');
      expect(v['City'], 'Toronto');
      expect(v['Stadium'], 'Rogers Centre');
      expect(v['Province/State'], 'ON');
      expect(v['Country Code'], 'CAN');
      expect(v['Country'], 'Canada');
      expect(v['MEID'], '776445455');
      expect(v['Headline'], 'Miami Marlins v Toronto Blue Jays');
      expect(v['Credit'], 'Getty Images');
      expect(v['Source'], 'Getty Images North America');
      expect(v['Copyright'], '2026 Getty Images');
      expect(v['Time and Date'], '2026-05-27');
      expect(
        v['Caption'],
        contains('<<enter caption here>>'),
      );
      expect(result.skippedCount, 2);
    });
  });

  group('formatExifDateTimeForPanel', () {
    test('drops sub-second precision from display', () {
      final formatted = IptcTemplateImportService.formatExifDateTimeForPanel({
        'DateTimeOriginal': '2026:05:27 14:30:45.123456789',
      });

      expect(formatted, '2026-05-27 14:30:45');
    });

    test('ignores SubSecTimeOriginal in display', () {
      final formatted = IptcTemplateImportService.formatExifDateTimeForPanel({
        'DateTimeOriginal': '2026:05:27 14:30:45',
        'SubSecTimeOriginal': '456789',
      });

      expect(formatted, '2026-05-27 14:30:45');
    });
  });
}
