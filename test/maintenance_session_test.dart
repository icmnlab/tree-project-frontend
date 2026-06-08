import 'package:flutter_test/flutter_test.dart';
import 'package:sustainable_treeai/utils/maintenance_session.dart';

void main() {
  group('maintenanceTreeIdOf', () {
    test('reads int id', () {
      expect(maintenanceTreeIdOf({'id': 42}), 42);
    });

    test('reads string id and uppercase ID key', () {
      expect(maintenanceTreeIdOf({'id': '7'}), 7);
      expect(maintenanceTreeIdOf({'ID': 9}), 9);
    });

    test('returns null when missing or non-numeric', () {
      expect(maintenanceTreeIdOf({}), isNull);
      expect(maintenanceTreeIdOf({'id': 'abc'}), isNull);
    });
  });

  group('isMaintenanceSessionPending', () {
    test('a normal tree not touched this session is pending', () {
      expect(
        isMaintenanceSessionPending(
          treeId: 1,
          completedThisSession: <int>{},
          addedThisSession: <int>{},
        ),
        isTrue,
      );
    });

    test('newly added tree this session is NOT pending（核心：新增樹不進待辦）', () {
      expect(
        isMaintenanceSessionPending(
          treeId: 100,
          completedThisSession: <int>{},
          addedThisSession: <int>{100},
        ),
        isFalse,
      );
    });

    test('completed tree this session is NOT pending', () {
      expect(
        isMaintenanceSessionPending(
          treeId: 5,
          completedThisSession: <int>{5},
          addedThisSession: <int>{},
        ),
        isFalse,
      );
    });

    test('null id is never pending', () {
      expect(
        isMaintenanceSessionPending(
          treeId: null,
          completedThisSession: <int>{},
          addedThisSession: <int>{},
        ),
        isFalse,
      );
    });

    test('end-to-end: only untouched trees survive the pending filter', () {
      final trees = [
        {'id': 1}, // 原本待辦
        {'id': 2}, // 本場已完成重測
        {'id': 3}, // 本場新增入庫
        {'id': 4}, // 原本待辦
        {'ID': 5}, // 大寫鍵，原本待辦
      ];
      final completed = <int>{2};
      final added = <int>{3};

      final pendingIds = trees
          .where((t) => isMaintenanceSessionPending(
                treeId: maintenanceTreeIdOf(t),
                completedThisSession: completed,
                addedThisSession: added,
              ))
          .map(maintenanceTreeIdOf)
          .toList();

      expect(pendingIds, [1, 4, 5]);
    });
  });
}
