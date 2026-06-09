import 'package:flutter_test/flutter_test.dart';
import 'package:sustainable_treeai/utils/transfer_result.dart';

void main() {
  group('treeSurveyIdFromIdMapping', () {
    test('回傳最後一筆的 tree_survey_id（數字）', () {
      expect(
        treeSurveyIdFromIdMapping([
          {'pending_id': 55, 'tree_survey_id': 7074},
          {'pending_id': 56, 'tree_survey_id': 7075},
        ]),
        7075,
      );
    });

    test('容忍字串 id', () {
      expect(
        treeSurveyIdFromIdMapping([
          {'pending_id': '56', 'tree_survey_id': '7075'},
        ]),
        7075,
      );
    });

    test('空串列回傳 null', () {
      expect(treeSurveyIdFromIdMapping([]), isNull);
    });

    test('非串列回傳 null', () {
      expect(treeSurveyIdFromIdMapping(null), isNull);
    });
  });

  group('treeSurveyIdFromTransfer', () {
    test('正常轉移：用 id_mapping', () {
      expect(
        treeSurveyIdFromTransfer({
          'success': true,
          'transferred_tree_ids': [7075],
          'id_mapping': [
            {'pending_id': 56, 'tree_survey_id': 7075},
          ],
        }),
        7075,
      );
    });

    test('id_mapping 缺漏時退回 transferred_tree_ids', () {
      expect(
        treeSurveyIdFromTransfer({
          'success': true,
          'transferred_tree_ids': [7075],
          'id_mapping': [],
        }),
        7075,
      );
    });

    test('冪等略過（皆空）→ null（這正是 bug 來源，需由表單 callback 補上）', () {
      expect(
        treeSurveyIdFromTransfer({
          'success': true,
          'transferred_tree_ids': [],
          'id_mapping': [],
        }),
        isNull,
      );
    });

    test('success != true → null', () {
      expect(
        treeSurveyIdFromTransfer({
          'success': false,
          'id_mapping': [
            {'tree_survey_id': 7075},
          ],
        }),
        isNull,
      );
    });

    test('null 回應 → null', () {
      expect(treeSurveyIdFromTransfer(null), isNull);
    });
  });
}
