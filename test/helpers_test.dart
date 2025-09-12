import 'package:flutter_test/flutter_test.dart';
import '../lib/helpers.dart';

void main() {
  group('normalizeSupplementalCategories', () {
    test('should normalize and deduplicate basic input', () {
      final result = normalizeSupplementalCategories(['SPO1', 'BBN1', 'BBA1']);
      expect(result, equals(['SPO1', 'BBN1', 'BBA1']));
    });

    test('should handle comma-separated input', () {
      final result = normalizeSupplementalCategories(['SPO1, BBN1, BBA1']);
      expect(result, equals(['SPO1', 'BBN1', 'BBA1']));
    });

    test('should handle mixed whitespace and commas', () {
      final result =
          normalizeSupplementalCategories(['SPO1,BBN1 BBA1', ' SPO2']);
      expect(result, equals(['SPO1', 'BBN1', 'BBA1', 'SPO2']));
    });

    test('should deduplicate while preserving order', () {
      final result = normalizeSupplementalCategories(['SPO1', 'SPO12', 'SPO1']);
      expect(result, equals(['SPO1', 'SPO12']));
    });

    test('should convert to uppercase', () {
      final result = normalizeSupplementalCategories(['spo1', 'bbn1', 'BBA1']);
      expect(result, equals(['SPO1', 'BBN1', 'BBA1']));
    });

    test('should handle empty inputs', () {
      final result = normalizeSupplementalCategories(['', '  ', '']);
      expect(result, equals([]));
    });

    test('should filter out empty values', () {
      final result =
          normalizeSupplementalCategories(['SPO1', '', 'BBN1', '  ', 'BBA1']);
      expect(result, equals(['SPO1', 'BBN1', 'BBA1']));
    });

    test('should handle complex mixed input', () {
      final result = normalizeSupplementalCategories([
        'SPO1, BBN1, BBA1',
        'SPOf BBN BBA',
        'SPO1', // duplicate should be filtered
        '', // empty should be filtered
      ]);
      expect(result, equals(['SPO1', 'BBN1', 'BBA1', 'SPOF', 'BBN', 'BBA']));
    });

    test('should handle acceptance test case', () {
      final result = normalizeSupplementalCategories(
          ['SPO1, BBN1, BBA1, SPO12, BBN12, BBA12']);
      expect(
          result, equals(['SPO1', 'BBN1', 'BBA1', 'SPO12', 'BBN12', 'BBA12']));
    });

    test('should handle edit scenario - change SPO1 to SPO12', () {
      // Simulate editing SPO1 to SPO12 in first field
      final result = normalizeSupplementalCategories(['SPO12', 'BBN1', 'BBA1']);
      expect(result, equals(['SPO12', 'BBN1', 'BBA1']));
      expect(result, isNot(contains('SPO1')));
    });
  });

  group('buildSupplementalCategoriesArgs', () {
    test('should build correct ExifTool args for non-empty input', () {
      final result = buildSupplementalCategoriesArgs(['SPO1', 'BBN1', 'BBA1']);
      expect(
          result,
          equals([
            '-XMP-photoshop:SupplementalCategories=',
            '-XMP-photoshop:SupplementalCategories+=SPO1',
            '-XMP-photoshop:SupplementalCategories+=BBN1',
            '-XMP-photoshop:SupplementalCategories+=BBA1',
          ]));
    });

    test('should clear field when input is empty', () {
      final result = buildSupplementalCategoriesArgs(['', '  ', '']);
      expect(result, equals(['-XMP-photoshop:SupplementalCategories=']));
    });

    test('should handle single value', () {
      final result = buildSupplementalCategoriesArgs(['SPO1']);
      expect(
          result,
          equals([
            '-XMP-photoshop:SupplementalCategories=',
            '-XMP-photoshop:SupplementalCategories+=SPO1',
          ]));
    });
  });
}
