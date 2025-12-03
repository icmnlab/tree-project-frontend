// ============================================================================
// V3 樹木影像服務完整測試套件
// ============================================================================
// 測試覆蓋:
// - TreeImage 模型序列化/反序列化
// - TreeImageType 枚舉處理
// - 影像元數據管理
// - 路徑處理與驗證
// - 影像索引操作
// ============================================================================

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

// ============================================================================
// 測試用影像類型枚舉（模擬實際服務）
// ============================================================================

/// 照片類型
enum TestTreeImageType {
  overview,      // 全景照
  trunk,         // 樹幹照
  dbhMeasure,    // DBH 測量照
  crown,         // 樹冠照
  damage,        // 損傷照
  leaf,          // 葉片照
  bark,          // 樹皮照
  other,         // 其他
}

// ============================================================================
// 測試用樹木照片模型
// ============================================================================

/// 樹木照片模型
class TestTreeImage {
  final String id;
  final String treeId;
  final String localPath;
  final String? remotePath;
  final TestTreeImageType type;
  final DateTime capturedAt;
  final Map<String, dynamic>? metadata;
  final bool isSynced;
  final String? thumbnailPath;

  TestTreeImage({
    required this.id,
    required this.treeId,
    required this.localPath,
    this.remotePath,
    required this.type,
    required this.capturedAt,
    this.metadata,
    this.isSynced = false,
    this.thumbnailPath,
  });

  factory TestTreeImage.fromJson(Map<String, dynamic> json) {
    return TestTreeImage(
      id: json['id'] as String,
      treeId: json['tree_id'] as String,
      localPath: json['local_path'] as String,
      remotePath: json['remote_path'] as String?,
      type: TestTreeImageType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => TestTreeImageType.other,
      ),
      capturedAt: DateTime.parse(json['captured_at']),
      metadata: json['metadata'] as Map<String, dynamic>?,
      isSynced: json['is_synced'] as bool? ?? false,
      thumbnailPath: json['thumbnail_path'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tree_id': treeId,
      'local_path': localPath,
      'remote_path': remotePath,
      'type': type.name,
      'captured_at': capturedAt.toIso8601String(),
      'metadata': metadata,
      'is_synced': isSynced,
      'thumbnail_path': thumbnailPath,
    };
  }

  TestTreeImage copyWith({
    String? id,
    String? treeId,
    String? localPath,
    String? remotePath,
    TestTreeImageType? type,
    DateTime? capturedAt,
    Map<String, dynamic>? metadata,
    bool? isSynced,
    String? thumbnailPath,
  }) {
    return TestTreeImage(
      id: id ?? this.id,
      treeId: treeId ?? this.treeId,
      localPath: localPath ?? this.localPath,
      remotePath: remotePath ?? this.remotePath,
      type: type ?? this.type,
      capturedAt: capturedAt ?? this.capturedAt,
      metadata: metadata ?? this.metadata,
      isSynced: isSynced ?? this.isSynced,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    );
  }
}

// ============================================================================
// 測試用影像索引管理器
// ============================================================================

class TestImageIndexManager {
  final Map<String, List<TestTreeImage>> _index = {};

  /// 加入影像
  void addImage(TestTreeImage image) {
    _index[image.treeId] ??= [];
    _index[image.treeId]!.add(image);
  }

  /// 取得樹木的所有影像
  List<TestTreeImage> getImagesForTree(String treeId) {
    return _index[treeId] ?? [];
  }

  /// 取得特定類型的影像
  List<TestTreeImage> getImagesByType(String treeId, TestTreeImageType type) {
    return getImagesForTree(treeId).where((img) => img.type == type).toList();
  }

  /// 刪除影像
  bool removeImage(String imageId) {
    for (final entry in _index.entries) {
      final index = entry.value.indexWhere((img) => img.id == imageId);
      if (index != -1) {
        entry.value.removeAt(index);
        return true;
      }
    }
    return false;
  }

  /// 更新影像同步狀態
  bool markAsSynced(String imageId) {
    for (final entry in _index.entries) {
      final index = entry.value.indexWhere((img) => img.id == imageId);
      if (index != -1) {
        entry.value[index] = entry.value[index].copyWith(isSynced: true);
        return true;
      }
    }
    return false;
  }

  /// 取得未同步的影像
  List<TestTreeImage> getUnsyncedImages() {
    return _index.values
        .expand((images) => images)
        .where((img) => !img.isSynced)
        .toList();
  }

  /// 取得所有影像數量
  int get totalImageCount => 
      _index.values.fold(0, (sum, list) => sum + list.length);

  /// 取得索引的 JSON 表示
  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{};
    _index.forEach((treeId, images) {
      result[treeId] = images.map((img) => img.toJson()).toList();
    });
    return result;
  }

  /// 從 JSON 載入索引
  void loadFromJson(Map<String, dynamic> json) {
    _index.clear();
    json.forEach((treeId, images) {
      _index[treeId] = (images as List)
          .map((img) => TestTreeImage.fromJson(img))
          .toList();
    });
  }

  /// 清空索引
  void clear() => _index.clear();
}

// ============================================================================
// 測試用路徑驗證器
// ============================================================================

class TestPathValidator {
  static const List<String> _validExtensions = ['.jpg', '.jpeg', '.png', '.webp', '.heic'];

  /// 驗證影像路徑格式
  static bool isValidImagePath(String path) {
    if (path.isEmpty) return false;
    final lowerPath = path.toLowerCase();
    return _validExtensions.any((ext) => lowerPath.endsWith(ext));
  }

  /// 從路徑提取副檔名
  static String? getExtension(String path) {
    if (!path.contains('.')) return null;
    return '.${path.split('.').last.toLowerCase()}';
  }

  /// 生成影像 ID
  static String generateImageId(String treeId, TestTreeImageType type) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${treeId}_${type.name}_$timestamp';
  }

  /// 驗證影像 ID 格式
  static bool isValidImageId(String id) {
    // 格式: {treeId}_{type}_{timestamp}
    final parts = id.split('_');
    if (parts.length < 3) return false;
    
    // 最後一部分應為時間戳
    final timestamp = int.tryParse(parts.last);
    return timestamp != null && timestamp > 0;
  }
}

// ============================================================================
// 測試用影像元數據處理器
// ============================================================================

class TestImageMetadataHandler {
  /// 驗證元數據完整性
  static bool validateMetadata(Map<String, dynamic>? metadata) {
    if (metadata == null) return true; // 允許空元數據
    
    // 檢查保留欄位的類型
    if (metadata.containsKey('gps_lat')) {
      if (metadata['gps_lat'] is! num) return false;
    }
    if (metadata.containsKey('gps_lon')) {
      if (metadata['gps_lon'] is! num) return false;
    }
    if (metadata.containsKey('accuracy')) {
      if (metadata['accuracy'] is! num) return false;
    }
    
    return true;
  }

  /// 合併元數據
  static Map<String, dynamic> mergeMetadata(
    Map<String, dynamic>? base,
    Map<String, dynamic>? overlay,
  ) {
    if (base == null && overlay == null) return {};
    if (base == null) return Map.from(overlay!);
    if (overlay == null) return Map.from(base);
    
    return {...base, ...overlay};
  }

  /// 提取 GPS 資訊
  static Map<String, double>? extractGpsInfo(Map<String, dynamic>? metadata) {
    if (metadata == null) return null;
    
    final lat = metadata['gps_lat'];
    final lon = metadata['gps_lon'];
    
    if (lat is num && lon is num) {
      return {
        'lat': lat.toDouble(),
        'lon': lon.toDouble(),
        'accuracy': (metadata['accuracy'] as num?)?.toDouble() ?? 0.0,
      };
    }
    
    return null;
  }
}

// ============================================================================
// 測試用同步狀態追蹤器
// ============================================================================

class TestSyncTracker {
  final Map<String, DateTime> _syncTimestamps = {};
  final Set<String> _failedSyncs = {};

  /// 記錄成功同步
  void recordSuccess(String imageId) {
    _syncTimestamps[imageId] = DateTime.now();
    _failedSyncs.remove(imageId);
  }

  /// 記錄失敗同步
  void recordFailure(String imageId) {
    _failedSyncs.add(imageId);
  }

  /// 檢查是否已同步
  bool isSynced(String imageId) => _syncTimestamps.containsKey(imageId);

  /// 取得同步時間
  DateTime? getSyncTime(String imageId) => _syncTimestamps[imageId];

  /// 取得失敗的同步
  Set<String> get failedSyncs => Set.from(_failedSyncs);

  /// 取得需要重試的項目
  List<String> getRetryList() => _failedSyncs.toList();

  /// 統計資訊
  Map<String, int> getStats() => {
    'synced': _syncTimestamps.length,
    'failed': _failedSyncs.length,
  };
}

// ============================================================================
// 測試套件
// ============================================================================

void main() {
  group('TreeImage 模型測試', () {
    test('應正確序列化為 JSON', () {
      final image = TestTreeImage(
        id: 'tree123_trunk_1234567890',
        treeId: 'tree123',
        localPath: '/path/to/image.jpg',
        type: TestTreeImageType.trunk,
        capturedAt: DateTime(2024, 1, 15, 10, 30),
        metadata: {'gps_lat': 23.5, 'gps_lon': 120.5},
        isSynced: false,
      );

      final json = image.toJson();

      expect(json['id'], 'tree123_trunk_1234567890');
      expect(json['tree_id'], 'tree123');
      expect(json['local_path'], '/path/to/image.jpg');
      expect(json['type'], 'trunk');
      expect(json['is_synced'], false);
      expect(json['metadata']['gps_lat'], 23.5);
    });

    test('應正確從 JSON 反序列化', () {
      final json = {
        'id': 'tree456_dbhMeasure_9876543210',
        'tree_id': 'tree456',
        'local_path': '/storage/images/test.png',
        'remote_path': 'https://example.com/image.png',
        'type': 'dbhMeasure',
        'captured_at': '2024-06-20T14:45:00.000',
        'metadata': {'accuracy': 5.0},
        'is_synced': true,
        'thumbnail_path': '/storage/images/test_thumb.png',
      };

      final image = TestTreeImage.fromJson(json);

      expect(image.id, 'tree456_dbhMeasure_9876543210');
      expect(image.treeId, 'tree456');
      expect(image.type, TestTreeImageType.dbhMeasure);
      expect(image.isSynced, true);
      expect(image.thumbnailPath, '/storage/images/test_thumb.png');
    });

    test('應處理未知的影像類型', () {
      final json = {
        'id': 'test_unknown_123',
        'tree_id': 'tree789',
        'local_path': '/path/image.jpg',
        'type': 'unknown_type',
        'captured_at': '2024-01-01T00:00:00.000',
      };

      final image = TestTreeImage.fromJson(json);

      expect(image.type, TestTreeImageType.other);
    });

    test('copyWith 應正確複製並更新', () {
      final original = TestTreeImage(
        id: 'img001',
        treeId: 'tree001',
        localPath: '/old/path.jpg',
        type: TestTreeImageType.overview,
        capturedAt: DateTime(2024, 1, 1),
        isSynced: false,
      );

      final updated = original.copyWith(
        isSynced: true,
        remotePath: 'https://cdn.example.com/img001.jpg',
      );

      expect(updated.id, original.id);
      expect(updated.treeId, original.treeId);
      expect(updated.isSynced, true);
      expect(updated.remotePath, 'https://cdn.example.com/img001.jpg');
      expect(original.isSynced, false); // 原始不變
    });
  });

  group('影像類型枚舉測試', () {
    test('應包含所有預期的類型', () {
      expect(TestTreeImageType.values.length, 8);
      expect(TestTreeImageType.values, contains(TestTreeImageType.overview));
      expect(TestTreeImageType.values, contains(TestTreeImageType.trunk));
      expect(TestTreeImageType.values, contains(TestTreeImageType.dbhMeasure));
      expect(TestTreeImageType.values, contains(TestTreeImageType.crown));
      expect(TestTreeImageType.values, contains(TestTreeImageType.damage));
      expect(TestTreeImageType.values, contains(TestTreeImageType.leaf));
      expect(TestTreeImageType.values, contains(TestTreeImageType.bark));
      expect(TestTreeImageType.values, contains(TestTreeImageType.other));
    });

    test('應正確轉換為字串', () {
      expect(TestTreeImageType.dbhMeasure.name, 'dbhMeasure');
      expect(TestTreeImageType.overview.name, 'overview');
    });
  });

  group('影像索引管理器測試', () {
    late TestImageIndexManager manager;

    setUp(() {
      manager = TestImageIndexManager();
    });

    test('應正確加入和取得影像', () {
      final image1 = TestTreeImage(
        id: 'img1',
        treeId: 'tree1',
        localPath: '/path/1.jpg',
        type: TestTreeImageType.trunk,
        capturedAt: DateTime.now(),
      );
      final image2 = TestTreeImage(
        id: 'img2',
        treeId: 'tree1',
        localPath: '/path/2.jpg',
        type: TestTreeImageType.crown,
        capturedAt: DateTime.now(),
      );

      manager.addImage(image1);
      manager.addImage(image2);

      final images = manager.getImagesForTree('tree1');
      expect(images.length, 2);
    });

    test('應按類型過濾影像', () {
      manager.addImage(TestTreeImage(
        id: 'trunk1',
        treeId: 'tree1',
        localPath: '/path/trunk1.jpg',
        type: TestTreeImageType.trunk,
        capturedAt: DateTime.now(),
      ));
      manager.addImage(TestTreeImage(
        id: 'crown1',
        treeId: 'tree1',
        localPath: '/path/crown1.jpg',
        type: TestTreeImageType.crown,
        capturedAt: DateTime.now(),
      ));
      manager.addImage(TestTreeImage(
        id: 'trunk2',
        treeId: 'tree1',
        localPath: '/path/trunk2.jpg',
        type: TestTreeImageType.trunk,
        capturedAt: DateTime.now(),
      ));

      final trunkImages = manager.getImagesByType('tree1', TestTreeImageType.trunk);
      expect(trunkImages.length, 2);
      expect(trunkImages.every((img) => img.type == TestTreeImageType.trunk), true);
    });

    test('應正確刪除影像', () {
      manager.addImage(TestTreeImage(
        id: 'to_delete',
        treeId: 'tree1',
        localPath: '/path/delete.jpg',
        type: TestTreeImageType.other,
        capturedAt: DateTime.now(),
      ));

      expect(manager.totalImageCount, 1);
      
      final result = manager.removeImage('to_delete');
      expect(result, true);
      expect(manager.totalImageCount, 0);
    });

    test('刪除不存在的影像應返回 false', () {
      final result = manager.removeImage('nonexistent');
      expect(result, false);
    });

    test('應正確標記為已同步', () {
      manager.addImage(TestTreeImage(
        id: 'sync_test',
        treeId: 'tree1',
        localPath: '/path/sync.jpg',
        type: TestTreeImageType.trunk,
        capturedAt: DateTime.now(),
        isSynced: false,
      ));

      final result = manager.markAsSynced('sync_test');
      expect(result, true);

      final images = manager.getImagesForTree('tree1');
      expect(images.first.isSynced, true);
    });

    test('應取得所有未同步的影像', () {
      manager.addImage(TestTreeImage(
        id: 'synced1',
        treeId: 'tree1',
        localPath: '/path/1.jpg',
        type: TestTreeImageType.trunk,
        capturedAt: DateTime.now(),
        isSynced: true,
      ));
      manager.addImage(TestTreeImage(
        id: 'unsynced1',
        treeId: 'tree1',
        localPath: '/path/2.jpg',
        type: TestTreeImageType.crown,
        capturedAt: DateTime.now(),
        isSynced: false,
      ));
      manager.addImage(TestTreeImage(
        id: 'unsynced2',
        treeId: 'tree2',
        localPath: '/path/3.jpg',
        type: TestTreeImageType.leaf,
        capturedAt: DateTime.now(),
        isSynced: false,
      ));

      final unsynced = manager.getUnsyncedImages();
      expect(unsynced.length, 2);
      expect(unsynced.every((img) => !img.isSynced), true);
    });

    test('應正確序列化和反序列化索引', () {
      manager.addImage(TestTreeImage(
        id: 'img1',
        treeId: 'tree1',
        localPath: '/path/1.jpg',
        type: TestTreeImageType.trunk,
        capturedAt: DateTime(2024, 6, 1),
      ));
      manager.addImage(TestTreeImage(
        id: 'img2',
        treeId: 'tree2',
        localPath: '/path/2.jpg',
        type: TestTreeImageType.crown,
        capturedAt: DateTime(2024, 6, 2),
      ));

      final json = manager.toJson();
      final jsonString = jsonEncode(json);

      // 建立新管理器並載入
      final newManager = TestImageIndexManager();
      newManager.loadFromJson(jsonDecode(jsonString));

      expect(newManager.totalImageCount, 2);
      expect(newManager.getImagesForTree('tree1').length, 1);
      expect(newManager.getImagesForTree('tree2').length, 1);
    });
  });

  group('路徑驗證器測試', () {
    test('應驗證有效的影像路徑', () {
      expect(TestPathValidator.isValidImagePath('/path/image.jpg'), true);
      expect(TestPathValidator.isValidImagePath('/path/image.JPEG'), true);
      expect(TestPathValidator.isValidImagePath('/path/image.png'), true);
      expect(TestPathValidator.isValidImagePath('/path/image.webp'), true);
      expect(TestPathValidator.isValidImagePath('/path/image.heic'), true);
    });

    test('應拒絕無效的影像路徑', () {
      expect(TestPathValidator.isValidImagePath('/path/image.gif'), false);
      expect(TestPathValidator.isValidImagePath('/path/image.bmp'), false);
      expect(TestPathValidator.isValidImagePath('/path/document.pdf'), false);
      expect(TestPathValidator.isValidImagePath(''), false);
    });

    test('應正確提取副檔名', () {
      expect(TestPathValidator.getExtension('/path/image.jpg'), '.jpg');
      expect(TestPathValidator.getExtension('/path/image.PNG'), '.png');
      expect(TestPathValidator.getExtension('/path/noext'), null);
    });

    test('應生成有效的影像 ID', () {
      final id = TestPathValidator.generateImageId('tree123', TestTreeImageType.trunk);
      
      expect(id.startsWith('tree123_trunk_'), true);
      expect(TestPathValidator.isValidImageId(id), true);
    });

    test('應驗證影像 ID 格式', () {
      expect(TestPathValidator.isValidImageId('tree1_trunk_1234567890'), true);
      expect(TestPathValidator.isValidImageId('tree1_dbhMeasure_9999999999'), true);
      expect(TestPathValidator.isValidImageId('invalid'), false);
      expect(TestPathValidator.isValidImageId('tree1_trunk'), false);
      expect(TestPathValidator.isValidImageId('tree1_trunk_notanumber'), false);
    });
  });

  group('元數據處理器測試', () {
    test('應驗證有效的元數據', () {
      expect(TestImageMetadataHandler.validateMetadata(null), true);
      expect(TestImageMetadataHandler.validateMetadata({}), true);
      expect(TestImageMetadataHandler.validateMetadata({
        'gps_lat': 23.5,
        'gps_lon': 120.5,
        'accuracy': 5.0,
      }), true);
    });

    test('應拒絕無效類型的元數據', () {
      expect(TestImageMetadataHandler.validateMetadata({
        'gps_lat': 'not a number',
      }), false);
      // 當 key 存在但值為 null 時，containsKey 返回 true，
      // 但 null is! num 也是 true，所以應該返回 false
      expect(TestImageMetadataHandler.validateMetadata({
        'gps_lon': null,
      }), false);
      expect(TestImageMetadataHandler.validateMetadata({
        'accuracy': 'high',
      }), false);
    });

    test('應正確合併元數據', () {
      final base = {'key1': 'value1', 'key2': 'value2'};
      final overlay = {'key2': 'updated', 'key3': 'value3'};

      final merged = TestImageMetadataHandler.mergeMetadata(base, overlay);

      expect(merged['key1'], 'value1');
      expect(merged['key2'], 'updated');
      expect(merged['key3'], 'value3');
    });

    test('應處理 null 元數據合併', () {
      expect(TestImageMetadataHandler.mergeMetadata(null, null), {});
      expect(TestImageMetadataHandler.mergeMetadata({'a': 1}, null), {'a': 1});
      expect(TestImageMetadataHandler.mergeMetadata(null, {'b': 2}), {'b': 2});
    });

    test('應正確提取 GPS 資訊', () {
      final metadata = {
        'gps_lat': 23.5,
        'gps_lon': 120.5,
        'accuracy': 3.0,
        'other': 'data',
      };

      final gps = TestImageMetadataHandler.extractGpsInfo(metadata);

      expect(gps, isNotNull);
      expect(gps!['lat'], 23.5);
      expect(gps['lon'], 120.5);
      expect(gps['accuracy'], 3.0);
    });

    test('應在缺少 GPS 時返回 null', () {
      expect(TestImageMetadataHandler.extractGpsInfo(null), null);
      expect(TestImageMetadataHandler.extractGpsInfo({}), null);
      expect(TestImageMetadataHandler.extractGpsInfo({'other': 'data'}), null);
      expect(TestImageMetadataHandler.extractGpsInfo({'gps_lat': 23.5}), null);
    });
  });

  group('同步追蹤器測試', () {
    late TestSyncTracker tracker;

    setUp(() {
      tracker = TestSyncTracker();
    });

    test('應記錄成功同步', () {
      tracker.recordSuccess('img1');

      expect(tracker.isSynced('img1'), true);
      expect(tracker.getSyncTime('img1'), isNotNull);
    });

    test('應記錄失敗同步', () {
      tracker.recordFailure('img2');

      expect(tracker.isSynced('img2'), false);
      expect(tracker.failedSyncs, contains('img2'));
    });

    test('成功同步應清除失敗記錄', () {
      tracker.recordFailure('img3');
      expect(tracker.failedSyncs, contains('img3'));

      tracker.recordSuccess('img3');
      expect(tracker.failedSyncs, isNot(contains('img3')));
      expect(tracker.isSynced('img3'), true);
    });

    test('應取得需要重試的列表', () {
      tracker.recordFailure('img1');
      tracker.recordFailure('img2');
      tracker.recordSuccess('img3');

      final retryList = tracker.getRetryList();
      expect(retryList.length, 2);
      expect(retryList, contains('img1'));
      expect(retryList, contains('img2'));
    });

    test('應提供正確的統計資訊', () {
      tracker.recordSuccess('s1');
      tracker.recordSuccess('s2');
      tracker.recordFailure('f1');

      final stats = tracker.getStats();
      expect(stats['synced'], 2);
      expect(stats['failed'], 1);
    });
  });

  group('整合測試', () {
    test('完整的影像生命週期', () {
      final manager = TestImageIndexManager();
      final tracker = TestSyncTracker();

      // 1. 建立影像
      final imageId = TestPathValidator.generateImageId('tree001', TestTreeImageType.dbhMeasure);
      final image = TestTreeImage(
        id: imageId,
        treeId: 'tree001',
        localPath: '/storage/tree_images/tree001/$imageId.jpg',
        type: TestTreeImageType.dbhMeasure,
        capturedAt: DateTime.now(),
        metadata: {
          'gps_lat': 23.97,
          'gps_lon': 120.68,
          'accuracy': 3.0,
          'dbh_cm': 45.5,
        },
        isSynced: false,
      );

      // 2. 驗證
      expect(TestPathValidator.isValidImageId(imageId), true);
      expect(TestImageMetadataHandler.validateMetadata(image.metadata), true);

      // 3. 加入索引
      manager.addImage(image);
      expect(manager.totalImageCount, 1);

      // 4. 模擬同步
      tracker.recordSuccess(imageId);
      manager.markAsSynced(imageId);

      // 5. 驗證同步狀態
      expect(tracker.isSynced(imageId), true);
      expect(manager.getImagesForTree('tree001').first.isSynced, true);
      expect(manager.getUnsyncedImages(), isEmpty);
    });

    test('多棵樹木的影像管理', () {
      final manager = TestImageIndexManager();
      final trees = ['tree001', 'tree002', 'tree003'];
      final types = [TestTreeImageType.trunk, TestTreeImageType.crown, TestTreeImageType.dbhMeasure];

      // 為每棵樹加入不同類型的影像
      for (final treeId in trees) {
        for (final type in types) {
          manager.addImage(TestTreeImage(
            id: TestPathValidator.generateImageId(treeId, type),
            treeId: treeId,
            localPath: '/path/$treeId/${type.name}.jpg',
            type: type,
            capturedAt: DateTime.now(),
          ));
        }
      }

      expect(manager.totalImageCount, 9);
      
      for (final treeId in trees) {
        expect(manager.getImagesForTree(treeId).length, 3);
        expect(manager.getImagesByType(treeId, TestTreeImageType.trunk).length, 1);
      }
    });
  });
}
