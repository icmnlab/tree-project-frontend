// ============================================================================
// V3 資料庫優化與 ML 數據收集系統測試
// ============================================================================
// 覆蓋範圍：
// 1. 資料庫正規化完整驗證 (1NF, 2NF, 3NF, BCNF)
// 2. 索引優化驗證
// 3. 圖片存儲策略
// 4. ML 數據收集後端 API
// 5. 兼容性驗證（舊版 APP 相容）
// ============================================================================

// dart:convert and dart:math imports removed - unused
import 'package:flutter_test/flutter_test.dart';

// ============================================================================
// Part 1: 完整資料庫正規化驗證
// ============================================================================

/// 資料庫欄位定義
class TestDBColumn {
  final String name;
  final String dataType;
  final bool isPrimaryKey;
  final bool isForeignKey;
  final String? foreignTable;
  final bool isNullable;
  final dynamic defaultValue;
  final List<String> functionalDependencies;  // 函數依賴
  
  const TestDBColumn({
    required this.name,
    required this.dataType,
    this.isPrimaryKey = false,
    this.isForeignKey = false,
    this.foreignTable,
    this.isNullable = true,
    this.defaultValue,
    this.functionalDependencies = const [],
  });
}

/// 資料庫表格定義
class TestDBTable {
  final String name;
  final List<TestDBColumn> columns;
  final List<String> primaryKey;
  final List<TestDBIndex> indexes;
  
  const TestDBTable({
    required this.name,
    required this.columns,
    required this.primaryKey,
    this.indexes = const [],
  });
  
  /// 獲取所有欄位名稱
  List<String> get columnNames => columns.map((c) => c.name).toList();
  
  /// 獲取非主鍵欄位
  List<TestDBColumn> get nonKeyColumns =>
      columns.where((c) => !primaryKey.contains(c.name)).toList();
}

/// 資料庫索引定義
class TestDBIndex {
  final String name;
  final List<String> columns;
  final bool isUnique;
  final String? condition;  // 部分索引條件
  
  const TestDBIndex({
    required this.name,
    required this.columns,
    this.isUnique = false,
    this.condition,
  });
}

/// 完整正規化驗證器
class TestNormalizationValidator {
  /// 驗證 1NF - 原子值
  static List<String> validate1NF(TestDBTable table) {
    final issues = <String>[];
    
    for (final column in table.columns) {
      // 檢查是否有陣列/列表類型（違反 1NF）
      if (column.dataType.contains('ARRAY') || 
          column.dataType.contains('[]')) {
        issues.add(
          '欄位 "${column.name}" 使用陣列類型，可能違反 1NF。'
          '建議拆分為獨立表格。'
        );
      }
      
      // 檢查 JSON 欄位（可能違反 1NF）
      if (column.dataType.toUpperCase() == 'JSON' ||
          column.dataType.toUpperCase() == 'JSONB') {
        issues.add(
          '欄位 "${column.name}" 使用 JSON 類型。'
          '若存儲結構化數據，建議考慮拆分為獨立表格以符合 1NF。'
        );
      }
    }
    
    // 檢查是否有主鍵
    if (table.primaryKey.isEmpty) {
      issues.add('表格 "${table.name}" 沒有主鍵，違反 1NF 要求。');
    }
    
    return issues;
  }
  
  /// 驗證 2NF - 完全函數依賴
  static List<String> validate2NF(TestDBTable table) {
    final issues = <String>[];
    
    // 只有複合主鍵時才需要檢查 2NF
    if (table.primaryKey.length <= 1) {
      return issues;  // 單一主鍵自動滿足 2NF
    }
    
    for (final column in table.nonKeyColumns) {
      // 檢查是否只依賴於部分主鍵
      final deps = column.functionalDependencies;
      if (deps.isNotEmpty) {
        final dependsOnPartialKey = deps.any((d) => 
          table.primaryKey.contains(d) && 
          !deps.toSet().containsAll(table.primaryKey)
        );
        
        if (dependsOnPartialKey) {
          issues.add(
            '欄位 "${column.name}" 只依賴於部分主鍵 ${deps}，違反 2NF。'
            '建議將其移至以 ${deps} 為主鍵的獨立表格。'
          );
        }
      }
    }
    
    return issues;
  }
  
  /// 驗證 3NF - 無傳遞依賴
  static List<String> validate3NF(TestDBTable table) {
    final issues = <String>[];
    
    for (final column in table.nonKeyColumns) {
      final deps = column.functionalDependencies;
      
      // 檢查是否通過非主鍵欄位傳遞依賴
      for (final dep in deps) {
        if (!table.primaryKey.contains(dep)) {
          // 依賴於非主鍵欄位 = 傳遞依賴
          issues.add(
            '欄位 "${column.name}" 通過 "$dep" 傳遞依賴於主鍵，違反 3NF。'
            '建議將 "${column.name}" 與 "$dep" 移至獨立表格。'
          );
        }
      }
    }
    
    return issues;
  }
  
  /// 驗證 BCNF - 每個決定因子都是候選鍵
  static List<String> validateBCNF(TestDBTable table) {
    final issues = <String>[];
    
    // BCNF 比 3NF 更嚴格
    // 每個函數依賴的左側（決定因子）都必須是超鍵
    
    for (final column in table.columns) {
      final deps = column.functionalDependencies;
      
      for (final dep in deps) {
        // 如果決定因子不是主鍵的一部分，則可能違反 BCNF
        if (!table.primaryKey.contains(dep) && dep.isNotEmpty) {
          final depColumn = table.columns.where((c) => c.name == dep);
          if (depColumn.isNotEmpty && !depColumn.first.isPrimaryKey) {
            issues.add(
              '函數依賴 "$dep → ${column.name}" 的決定因子不是超鍵，'
              '可能違反 BCNF。'
            );
          }
        }
      }
    }
    
    return issues;
  }
  
  /// 完整正規化檢查
  static NormalizationReport fullValidation(TestDBTable table) {
    return NormalizationReport(
      tableName: table.name,
      nf1Issues: validate1NF(table),
      nf2Issues: validate2NF(table),
      nf3Issues: validate3NF(table),
      bcnfIssues: validateBCNF(table),
    );
  }
}

/// 正規化報告
class NormalizationReport {
  final String tableName;
  final List<String> nf1Issues;
  final List<String> nf2Issues;
  final List<String> nf3Issues;
  final List<String> bcnfIssues;
  
  NormalizationReport({
    required this.tableName,
    required this.nf1Issues,
    required this.nf2Issues,
    required this.nf3Issues,
    required this.bcnfIssues,
  });
  
  /// 最高滿足的正規化等級
  String get highestNF {
    if (nf1Issues.isNotEmpty) return 'UNF (未正規化)';
    if (nf2Issues.isNotEmpty) return '1NF';
    if (nf3Issues.isNotEmpty) return '2NF';
    if (bcnfIssues.isNotEmpty) return '3NF';
    return 'BCNF';
  }
  
  /// 所有問題
  List<String> get allIssues => [...nf1Issues, ...nf2Issues, ...nf3Issues, ...bcnfIssues];
  
  /// 是否完全符合 2NF
  bool get is2NF => nf1Issues.isEmpty && nf2Issues.isEmpty;
  
  /// 是否完全符合 3NF
  bool get is3NF => is2NF && nf3Issues.isEmpty;
}

// ============================================================================
// Part 2: 索引優化驗證
// ============================================================================

/// 索引優化建議器
class TestIndexOptimizer {
  /// 分析查詢模式並建議索引
  static List<IndexRecommendation> analyzeQueries(
    TestDBTable table,
    List<QueryPattern> queries,
  ) {
    final recommendations = <IndexRecommendation>[];
    final columnUsage = <String, int>{};
    
    // 統計欄位使用頻率
    for (final query in queries) {
      for (final col in query.whereColumns) {
        columnUsage[col] = (columnUsage[col] ?? 0) + query.frequency;
      }
      for (final col in query.orderByColumns) {
        columnUsage[col] = (columnUsage[col] ?? 0) + (query.frequency ~/ 2);
      }
    }
    
    // 現有索引覆蓋的欄位
    final indexedColumns = <String>{};
    for (final idx in table.indexes) {
      indexedColumns.addAll(idx.columns);
    }
    
    // 推薦缺少的索引
    for (final entry in columnUsage.entries) {
      if (entry.value >= 100 && !indexedColumns.contains(entry.key)) {
        recommendations.add(IndexRecommendation(
          column: entry.key,
          reason: '高頻查詢欄位 (使用 ${entry.value} 次)',
          priority: entry.value >= 500 ? 'HIGH' : 'MEDIUM',
        ));
      }
    }
    
    // 檢查複合索引機會
    for (final query in queries) {
      if (query.whereColumns.length >= 2 && query.frequency >= 50) {
        final compositeKey = query.whereColumns.join('_');
        final hasCompositeIndex = table.indexes.any((idx) =>
          idx.columns.length >= 2 &&
          idx.columns.take(query.whereColumns.length).toList().join('_') == compositeKey
        );
        
        if (!hasCompositeIndex) {
          recommendations.add(IndexRecommendation(
            column: query.whereColumns.join(', '),
            reason: '複合查詢條件 (使用 ${query.frequency} 次)',
            priority: 'MEDIUM',
            suggestedSql: 'CREATE INDEX idx_${table.name}_$compositeKey ON ${table.name}(${query.whereColumns.join(', ')});',
          ));
        }
      }
    }
    
    return recommendations;
  }
  
  /// 驗證現有索引效率
  static List<String> validateIndexes(TestDBTable table) {
    final issues = <String>[];
    
    // 檢查重複索引
    final indexSignatures = <String>[];
    for (final idx in table.indexes) {
      final sig = idx.columns.join(',');
      if (indexSignatures.contains(sig)) {
        issues.add('索引 "${idx.name}" 與其他索引重複');
      }
      indexSignatures.add(sig);
    }
    
    // 檢查主鍵是否有索引（通常自動創建）
    if (table.primaryKey.isNotEmpty) {
      final pkIndexed = table.indexes.any((idx) =>
        idx.columns.first == table.primaryKey.first
      );
      if (!pkIndexed) {
        // 主鍵通常自動有索引，這裡只是提醒
      }
    }
    
    // 檢查外鍵是否有索引
    for (final col in table.columns) {
      if (col.isForeignKey) {
        final fkIndexed = table.indexes.any((idx) =>
          idx.columns.contains(col.name)
        );
        if (!fkIndexed) {
          issues.add('外鍵欄位 "${col.name}" 缺少索引，可能影響 JOIN 效能');
        }
      }
    }
    
    return issues;
  }
}

/// 查詢模式
class QueryPattern {
  final String description;
  final List<String> whereColumns;
  final List<String> orderByColumns;
  final int frequency;  // 預估每日使用次數
  
  const QueryPattern({
    required this.description,
    required this.whereColumns,
    this.orderByColumns = const [],
    required this.frequency,
  });
}

/// 索引建議
class IndexRecommendation {
  final String column;
  final String reason;
  final String priority;
  final String? suggestedSql;
  
  const IndexRecommendation({
    required this.column,
    required this.reason,
    required this.priority,
    this.suggestedSql,
  });
}

// ============================================================================
// Part 3: 圖片存儲策略驗證
// ============================================================================

/// 圖片存儲策略
enum ImageStorageStrategy {
  localOnly,       // 僅本地
  cloudSync,       // 雲端同步
  hybridWithCDN,   // 混合 + CDN
}

/// 圖片存儲配置
class TestImageStorageConfig {
  final ImageStorageStrategy strategy;
  final int maxLocalStorageMB;
  final int thumbnailQuality;  // 0-100
  final int fullImageQuality;  // 0-100
  final List<String> allowedFormats;
  final int maxFileSizeMB;
  
  const TestImageStorageConfig({
    required this.strategy,
    required this.maxLocalStorageMB,
    this.thumbnailQuality = 60,
    this.fullImageQuality = 85,
    this.allowedFormats = const ['jpg', 'jpeg', 'png', 'webp'],
    this.maxFileSizeMB = 10,
  });
}

/// 圖片存儲驗證器
class TestImageStorageValidator {
  /// 驗證存儲配置
  static List<String> validateConfig(TestImageStorageConfig config) {
    final issues = <String>[];
    
    if (config.maxLocalStorageMB < 100) {
      issues.add('本地存儲空間過小 (${config.maxLocalStorageMB}MB)，建議至少 100MB');
    }
    
    if (config.thumbnailQuality < 30 || config.thumbnailQuality > 90) {
      issues.add('縮圖品質 ${config.thumbnailQuality} 不在建議範圍 (30-90)');
    }
    
    if (config.fullImageQuality < 70) {
      issues.add('原圖品質 ${config.fullImageQuality} 過低，可能影響 ML 訓練');
    }
    
    if (!config.allowedFormats.contains('jpg') && 
        !config.allowedFormats.contains('jpeg')) {
      issues.add('建議支援 JPEG 格式以確保兼容性');
    }
    
    if (config.maxFileSizeMB > 20) {
      issues.add('單檔大小限制 ${config.maxFileSizeMB}MB 過大，可能影響上傳速度');
    }
    
    return issues;
  }
  
  /// 驗證圖片命名規則
  static bool isValidImageName(String fileName) {
    // 格式: {treeId}_{timestamp}_{type}.{ext}
    // treeId 可以包含字母、數字、底線、連字符
    // timestamp 是 13 位數字
    // type 可以包含字母和大小寫
    final pattern = RegExp(r'^[a-zA-Z0-9_-]+_\d{13}_[a-zA-Z]+\.(jpg|jpeg|png|webp)$');
    return pattern.hasMatch(fileName);
  }
  
  /// 計算預估存儲需求
  static StorageEstimate estimateStorage({
    required int treeCount,
    required int avgPhotosPerTree,
    required double avgPhotoSizeMB,
  }) {
    final totalPhotos = treeCount * avgPhotosPerTree;
    final totalSizeMB = totalPhotos * avgPhotoSizeMB;
    final thumbnailSizeMB = totalPhotos * 0.05;  // 縮圖約 50KB
    
    return StorageEstimate(
      totalPhotos: totalPhotos,
      fullImageSizeMB: totalSizeMB,
      thumbnailSizeMB: thumbnailSizeMB,
      totalSizeMB: totalSizeMB + thumbnailSizeMB,
    );
  }
}

/// 存儲估算
class StorageEstimate {
  final int totalPhotos;
  final double fullImageSizeMB;
  final double thumbnailSizeMB;
  final double totalSizeMB;
  
  const StorageEstimate({
    required this.totalPhotos,
    required this.fullImageSizeMB,
    required this.thumbnailSizeMB,
    required this.totalSizeMB,
  });
  
  double get totalSizeGB => totalSizeMB / 1024;
}

// ============================================================================
// Part 4: ML 數據收集後端 API 驗證
// ============================================================================

/// ML 數據上傳批次
class TestMLDataBatch {
  final String batchId;
  final List<Map<String, dynamic>> records;
  final DateTime createdAt;
  final String deviceId;
  final String appVersion;
  
  TestMLDataBatch({
    required this.batchId,
    required this.records,
    required this.createdAt,
    required this.deviceId,
    required this.appVersion,
  });
  
  Map<String, dynamic> toJson() => {
    'batch_id': batchId,
    'records': records,
    'created_at': createdAt.toIso8601String(),
    'device_id': deviceId,
    'app_version': appVersion,
    'record_count': records.length,
  };
}

/// ML 後端 API 模擬
class TestMLBackendAPI {
  final List<TestMLDataBatch> _storedBatches = [];
  final Map<String, List<String>> _imageLinks = {};  // record_id -> image_paths
  
  /// 上傳數據批次
  Future<UploadResult> uploadBatch(TestMLDataBatch batch) async {
    // 驗證批次
    final errors = _validateBatch(batch);
    if (errors.isNotEmpty) {
      return UploadResult(
        success: false,
        batchId: batch.batchId,
        errors: errors,
      );
    }
    
    _storedBatches.add(batch);
    
    return UploadResult(
      success: true,
      batchId: batch.batchId,
      recordCount: batch.records.length,
    );
  }
  
  /// 驗證批次
  List<String> _validateBatch(TestMLDataBatch batch) {
    final errors = <String>[];
    
    if (batch.records.isEmpty) {
      errors.add('批次不能為空');
    }
    
    if (batch.records.length > 1000) {
      errors.add('批次記錄數超過限制 (1000)');
    }
    
    for (var i = 0; i < batch.records.length; i++) {
      final record = batch.records[i];
      if (!record.containsKey('record_type')) {
        errors.add('記錄 $i 缺少 record_type');
      }
      if (!record.containsKey('timestamp')) {
        errors.add('記錄 $i 缺少 timestamp');
      }
    }
    
    return errors;
  }
  
  /// 上傳關聯圖片
  Future<UploadResult> uploadImage({
    required String recordId,
    required String imagePath,
    required int fileSizeBytes,
  }) async {
    if (fileSizeBytes > 10 * 1024 * 1024) {  // 10MB
      return UploadResult(
        success: false,
        errors: ['圖片大小超過限制 (10MB)'],
      );
    }
    
    _imageLinks.putIfAbsent(recordId, () => []);
    _imageLinks[recordId]!.add(imagePath);
    
    return UploadResult(
      success: true,
      recordCount: 1,
    );
  }
  
  /// 獲取統計資訊
  MLDataStatistics getStatistics() {
    int totalRecords = 0;
    final typeCount = <String, int>{};
    
    for (final batch in _storedBatches) {
      totalRecords += batch.records.length;
      for (final record in batch.records) {
        final type = record['record_type'] as String? ?? 'unknown';
        typeCount[type] = (typeCount[type] ?? 0) + 1;
      }
    }
    
    return MLDataStatistics(
      totalBatches: _storedBatches.length,
      totalRecords: totalRecords,
      totalImages: _imageLinks.values.fold(0, (sum, list) => sum + list.length),
      recordsByType: typeCount,
    );
  }
}

/// 上傳結果
class UploadResult {
  final bool success;
  final String? batchId;
  final int? recordCount;
  final List<String> errors;
  
  UploadResult({
    required this.success,
    this.batchId,
    this.recordCount,
    this.errors = const [],
  });
}

/// ML 數據統計
class MLDataStatistics {
  final int totalBatches;
  final int totalRecords;
  final int totalImages;
  final Map<String, int> recordsByType;
  
  MLDataStatistics({
    required this.totalBatches,
    required this.totalRecords,
    required this.totalImages,
    required this.recordsByType,
  });
}

// ============================================================================
// Part 5: 兼容性驗證
// ============================================================================

/// 版本兼容性驗證器
class TestCompatibilityValidator {
  /// 驗證資料庫遷移兼容性
  static List<String> validateMigration(
    TestDBTable oldSchema,
    TestDBTable newSchema,
  ) {
    final issues = <String>[];
    
    // 檢查是否有欄位被刪除
    for (final oldCol in oldSchema.columns) {
      final exists = newSchema.columns.any((c) => c.name == oldCol.name);
      if (!exists) {
        issues.add('欄位 "${oldCol.name}" 被刪除，可能影響舊版 APP');
      }
    }
    
    // 檢查是否有欄位類型變更
    for (final oldCol in oldSchema.columns) {
      final newCol = newSchema.columns.where((c) => c.name == oldCol.name).firstOrNull;
      if (newCol != null && oldCol.dataType != newCol.dataType) {
        issues.add(
          '欄位 "${oldCol.name}" 類型從 ${oldCol.dataType} 變更為 ${newCol.dataType}'
        );
      }
    }
    
    // 檢查新增的非空欄位
    for (final newCol in newSchema.columns) {
      final isNew = !oldSchema.columns.any((c) => c.name == newCol.name);
      if (isNew && !newCol.isNullable && newCol.defaultValue == null) {
        issues.add(
          '新增欄位 "${newCol.name}" 為非空且無預設值，會導致現有資料錯誤'
        );
      }
    }
    
    return issues;
  }
  
  /// 驗證 API 兼容性
  static List<String> validateAPICompatibility(
    Map<String, dynamic> oldResponse,
    Map<String, dynamic> newResponse,
  ) {
    final issues = <String>[];
    
    // 檢查是否有欄位被移除
    for (final key in oldResponse.keys) {
      if (!newResponse.containsKey(key)) {
        issues.add('API 回應欄位 "$key" 被移除');
      }
    }
    
    // 檢查欄位類型變更
    for (final key in oldResponse.keys) {
      if (newResponse.containsKey(key)) {
        final oldType = oldResponse[key].runtimeType;
        final newType = newResponse[key].runtimeType;
        if (oldType != newType && newResponse[key] != null) {
          issues.add(
            'API 欄位 "$key" 類型從 $oldType 變更為 $newType'
          );
        }
      }
    }
    
    return issues;
  }
}

// ============================================================================
// 測試套件
// ============================================================================

void main() {
  // =========================================================================
  // 資料庫正規化測試
  // =========================================================================
  
  group('資料庫正規化驗證', () {
    test('tree_survey 表格正規化分析', () {
      final treeSurveyTable = TestDBTable(
        name: 'tree_survey',
        primaryKey: ['id'],
        columns: [
          TestDBColumn(name: 'id', dataType: 'SERIAL', isPrimaryKey: true),
          TestDBColumn(name: 'project_code', dataType: 'VARCHAR'),
          TestDBColumn(name: 'project_name', dataType: 'VARCHAR', 
            functionalDependencies: ['project_code']),  // 傳遞依賴！
          TestDBColumn(name: 'species_id', dataType: 'VARCHAR'),
          TestDBColumn(name: 'species_name', dataType: 'VARCHAR',
            functionalDependencies: ['species_id']),  // 傳遞依賴！
          TestDBColumn(name: 'dbh_cm', dataType: 'DOUBLE PRECISION'),
          TestDBColumn(name: 'x_coord', dataType: 'DOUBLE PRECISION'),
          TestDBColumn(name: 'y_coord', dataType: 'DOUBLE PRECISION'),
        ],
        indexes: [
          TestDBIndex(name: 'idx_project_code', columns: ['project_code']),
          TestDBIndex(name: 'idx_species_name', columns: ['species_name']),
        ],
      );
      
      final report = TestNormalizationValidator.fullValidation(treeSurveyTable);
      
      // 輸出分析報告
      print('=== ${report.tableName} 正規化分析 ===');
      print('最高滿足: ${report.highestNF}');
      if (report.allIssues.isNotEmpty) {
        print('問題:');
        for (final issue in report.allIssues) {
          print('  - $issue');
        }
      }
      
      // 驗證至少滿足 2NF
      expect(report.is2NF, true, reason: 'tree_survey 應至少滿足 2NF');
    });
    
    test('pending_tree_measurements 表格正規化分析', () {
      final pendingTable = TestDBTable(
        name: 'pending_tree_measurements',
        primaryKey: ['id'],
        columns: [
          TestDBColumn(name: 'id', dataType: 'SERIAL', isPrimaryKey: true),
          TestDBColumn(name: 'batch_id', dataType: 'UUID'),
          TestDBColumn(name: 'tree_id', dataType: 'VARCHAR'),
          TestDBColumn(name: 'species_id', dataType: 'INTEGER', isForeignKey: true, foreignTable: 'tree_species'),
          TestDBColumn(name: 'species_name', dataType: 'VARCHAR'),  // 冗余！
          TestDBColumn(name: 'x_coord', dataType: 'DOUBLE PRECISION'),
          TestDBColumn(name: 'y_coord', dataType: 'DOUBLE PRECISION'),
          TestDBColumn(name: 'station_x', dataType: 'DOUBLE PRECISION'),
          TestDBColumn(name: 'station_y', dataType: 'DOUBLE PRECISION'),
          TestDBColumn(name: 'dbh_cm', dataType: 'DOUBLE PRECISION'),
          TestDBColumn(name: 'status', dataType: 'VARCHAR'),
          TestDBColumn(name: 'metadata', dataType: 'JSONB'),  // 1NF 注意
        ],
        indexes: [
          TestDBIndex(name: 'idx_batch_id', columns: ['batch_id']),
          TestDBIndex(name: 'idx_status', columns: ['status']),
        ],
      );
      
      final report = TestNormalizationValidator.fullValidation(pendingTable);
      
      // JSONB 會觸發 1NF 警告
      expect(report.nf1Issues.length, greaterThan(0));
      
      // 但這是可接受的設計決策（metadata 用於儲存非結構化數據）
      print('1NF 警告 (JSONB): ${report.nf1Issues.length} 個');
    });
    
    test('理想的正規化設計', () {
      // 展示一個完全符合 3NF 的設計
      final projectTable = TestDBTable(
        name: 'projects',
        primaryKey: ['id'],
        columns: [
          TestDBColumn(name: 'id', dataType: 'SERIAL', isPrimaryKey: true),
          TestDBColumn(name: 'code', dataType: 'VARCHAR'),
          TestDBColumn(name: 'name', dataType: 'VARCHAR'),
          TestDBColumn(name: 'area_id', dataType: 'INTEGER', isForeignKey: true),
        ],
        indexes: [
          TestDBIndex(name: 'idx_code', columns: ['code'], isUnique: true),
        ],
      );
      
      final report = TestNormalizationValidator.fullValidation(projectTable);
      
      expect(report.is3NF, true, reason: 'projects 表格應完全符合 3NF');
      expect(report.allIssues, isEmpty);
    });
  });
  
  // =========================================================================
  // 索引優化測試
  // =========================================================================
  
  group('索引優化驗證', () {
    test('查詢模式分析與索引建議', () {
      final table = TestDBTable(
        name: 'tree_survey',
        primaryKey: ['id'],
        columns: [
          TestDBColumn(name: 'id', dataType: 'SERIAL', isPrimaryKey: true),
          TestDBColumn(name: 'project_code', dataType: 'VARCHAR'),
          TestDBColumn(name: 'species_name', dataType: 'VARCHAR'),
          TestDBColumn(name: 'status', dataType: 'VARCHAR'),
          TestDBColumn(name: 'created_at', dataType: 'TIMESTAMP'),
        ],
        indexes: [
          TestDBIndex(name: 'idx_project_code', columns: ['project_code']),
        ],
      );
      
      final queries = [
        QueryPattern(
          description: '按專案列出樹木',
          whereColumns: ['project_code'],
          frequency: 500,
        ),
        QueryPattern(
          description: '按樹種統計',
          whereColumns: ['species_name'],
          frequency: 200,
        ),
        QueryPattern(
          description: '專案內按樹種查詢',
          whereColumns: ['project_code', 'species_name'],
          frequency: 150,
        ),
        QueryPattern(
          description: '按狀態過濾',
          whereColumns: ['status'],
          frequency: 300,
        ),
      ];
      
      final recommendations = TestIndexOptimizer.analyzeQueries(table, queries);
      
      // 應該建議 species_name 和 status 索引
      expect(recommendations.length, greaterThan(0));
      
      final speciesRec = recommendations.where((r) => r.column.contains('species_name'));
      expect(speciesRec.isNotEmpty, true);
      
      print('=== 索引建議 ===');
      for (final rec in recommendations) {
        print('${rec.priority}: ${rec.column} - ${rec.reason}');
      }
    });
    
    test('外鍵索引檢查', () {
      final table = TestDBTable(
        name: 'tree_survey',
        primaryKey: ['id'],
        columns: [
          TestDBColumn(name: 'id', dataType: 'SERIAL', isPrimaryKey: true),
          TestDBColumn(name: 'species_id', dataType: 'INTEGER', 
            isForeignKey: true, foreignTable: 'tree_species'),
          TestDBColumn(name: 'project_id', dataType: 'INTEGER',
            isForeignKey: true, foreignTable: 'projects'),
        ],
        indexes: [
          // 只有 species_id 有索引
          TestDBIndex(name: 'idx_species', columns: ['species_id']),
        ],
      );
      
      final issues = TestIndexOptimizer.validateIndexes(table);
      
      // 應該報告 project_id 缺少索引
      expect(issues.length, greaterThan(0));
      expect(issues.any((i) => i.contains('project_id')), true);
    });
  });
  
  // =========================================================================
  // 圖片存儲測試
  // =========================================================================
  
  group('圖片存儲策略驗證', () {
    test('合理的存儲配置', () {
      const config = TestImageStorageConfig(
        strategy: ImageStorageStrategy.hybridWithCDN,
        maxLocalStorageMB: 500,
        thumbnailQuality: 60,
        fullImageQuality: 85,
      );
      
      final issues = TestImageStorageValidator.validateConfig(config);
      expect(issues, isEmpty);
    });
    
    test('不合理的存儲配置應該報警', () {
      const config = TestImageStorageConfig(
        strategy: ImageStorageStrategy.localOnly,
        maxLocalStorageMB: 50,  // 太小
        thumbnailQuality: 95,    // 太高
        fullImageQuality: 50,    // 太低
        maxFileSizeMB: 50,       // 太大
      );
      
      final issues = TestImageStorageValidator.validateConfig(config);
      expect(issues.length, greaterThan(2));
    });
    
    test('圖片命名規則驗證', () {
      // 有效名稱
      expect(
        TestImageStorageValidator.isValidImageName('tree123_1701590400000_trunk.jpg'),
        true,
      );
      expect(
        TestImageStorageValidator.isValidImageName('ST-001_1701590400000_dbhMeasure.png'),
        true,
      );
      
      // 無效名稱
      expect(
        TestImageStorageValidator.isValidImageName('photo.jpg'),
        false,
      );
      expect(
        TestImageStorageValidator.isValidImageName('tree123_abc_trunk.jpg'),
        false,
      );
    });
    
    test('存儲需求估算', () {
      final estimate = TestImageStorageValidator.estimateStorage(
        treeCount: 10000,
        avgPhotosPerTree: 3,
        avgPhotoSizeMB: 2.0,
      );
      
      expect(estimate.totalPhotos, 30000);
      expect(estimate.fullImageSizeMB, closeTo(60000, 100));
      // 總計 = 60000 + 1500 (縮圖) = 61500 MB = ~60.06 GB
      expect(estimate.totalSizeGB, closeTo(60.0, 2));
      
      print('=== 存儲估算 ===');
      print('總照片數: ${estimate.totalPhotos}');
      print('原圖大小: ${estimate.fullImageSizeMB.toStringAsFixed(0)} MB');
      print('縮圖大小: ${estimate.thumbnailSizeMB.toStringAsFixed(0)} MB');
      print('總計: ${estimate.totalSizeGB.toStringAsFixed(1)} GB');
    });
  });
  
  // =========================================================================
  // ML 數據收集後端測試
  // =========================================================================
  
  group('ML 數據收集後端 API', () {
    late TestMLBackendAPI api;
    
    setUp(() {
      api = TestMLBackendAPI();
    });
    
    test('上傳有效批次', () async {
      final batch = TestMLDataBatch(
        batchId: 'batch_001',
        records: [
          {
            'record_type': 'arMeasurement',
            'timestamp': DateTime.now().toIso8601String(),
            'auto_values': {'dbh_cm': 25.0},
            'user_values': {'dbh_cm': 27.0},
          },
          {
            'record_type': 'speciesIdentification',
            'timestamp': DateTime.now().toIso8601String(),
            'auto_values': {'species_id': '0001'},
            'user_values': {'species_id': '0002'},
          },
        ],
        createdAt: DateTime.now(),
        deviceId: 'device_001',
        appVersion: '17.0.0',
      );
      
      final result = await api.uploadBatch(batch);
      
      expect(result.success, true);
      expect(result.recordCount, 2);
    });
    
    test('空批次應該被拒絕', () async {
      final batch = TestMLDataBatch(
        batchId: 'batch_empty',
        records: [],
        createdAt: DateTime.now(),
        deviceId: 'device_001',
        appVersion: '17.0.0',
      );
      
      final result = await api.uploadBatch(batch);
      
      expect(result.success, false);
      expect(result.errors, contains(predicate<String>((s) => s.contains('空'))));
    });
    
    test('超大批次應該被拒絕', () async {
      final records = List.generate(1500, (i) => {
        'record_type': 'arMeasurement',
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      final batch = TestMLDataBatch(
        batchId: 'batch_large',
        records: records,
        createdAt: DateTime.now(),
        deviceId: 'device_001',
        appVersion: '17.0.0',
      );
      
      final result = await api.uploadBatch(batch);
      
      expect(result.success, false);
      expect(result.errors, contains(predicate<String>((s) => s.contains('1000'))));
    });
    
    test('上傳關聯圖片', () async {
      final result = await api.uploadImage(
        recordId: 'record_001',
        imagePath: '/images/tree_001.jpg',
        fileSizeBytes: 2 * 1024 * 1024,  // 2MB
      );
      
      expect(result.success, true);
    });
    
    test('超大圖片應該被拒絕', () async {
      final result = await api.uploadImage(
        recordId: 'record_001',
        imagePath: '/images/huge.jpg',
        fileSizeBytes: 15 * 1024 * 1024,  // 15MB
      );
      
      expect(result.success, false);
    });
    
    test('統計資訊正確', () async {
      // 上傳多個批次
      for (var i = 0; i < 5; i++) {
        await api.uploadBatch(TestMLDataBatch(
          batchId: 'batch_$i',
          records: List.generate(10, (j) => {
            'record_type': j % 2 == 0 ? 'arMeasurement' : 'speciesIdentification',
            'timestamp': DateTime.now().toIso8601String(),
          }),
          createdAt: DateTime.now(),
          deviceId: 'device_001',
          appVersion: '17.0.0',
        ));
      }
      
      final stats = api.getStatistics();
      
      expect(stats.totalBatches, 5);
      expect(stats.totalRecords, 50);
      expect(stats.recordsByType['arMeasurement'], 25);
      expect(stats.recordsByType['speciesIdentification'], 25);
    });
  });
  
  // =========================================================================
  // 兼容性測試
  // =========================================================================
  
  group('版本兼容性驗證', () {
    test('安全的資料庫遷移', () {
      final oldSchema = TestDBTable(
        name: 'tree_survey',
        primaryKey: ['id'],
        columns: [
          TestDBColumn(name: 'id', dataType: 'SERIAL'),
          TestDBColumn(name: 'species_name', dataType: 'VARCHAR'),
          TestDBColumn(name: 'dbh_cm', dataType: 'DOUBLE PRECISION'),
        ],
        indexes: [],
      );
      
      final newSchema = TestDBTable(
        name: 'tree_survey',
        primaryKey: ['id'],
        columns: [
          TestDBColumn(name: 'id', dataType: 'SERIAL'),
          TestDBColumn(name: 'species_name', dataType: 'VARCHAR'),
          TestDBColumn(name: 'dbh_cm', dataType: 'DOUBLE PRECISION'),
          // 新增可空欄位（安全）
          TestDBColumn(name: 'is_placeholder', dataType: 'BOOLEAN', 
            isNullable: true, defaultValue: false),
        ],
        indexes: [],
      );
      
      final issues = TestCompatibilityValidator.validateMigration(oldSchema, newSchema);
      expect(issues, isEmpty, reason: '新增可空欄位應該是兼容的');
    });
    
    test('不安全的資料庫遷移應該報警', () {
      final oldSchema = TestDBTable(
        name: 'tree_survey',
        primaryKey: ['id'],
        columns: [
          TestDBColumn(name: 'id', dataType: 'SERIAL'),
          TestDBColumn(name: 'old_field', dataType: 'VARCHAR'),
        ],
        indexes: [],
      );
      
      final newSchema = TestDBTable(
        name: 'tree_survey',
        primaryKey: ['id'],
        columns: [
          TestDBColumn(name: 'id', dataType: 'SERIAL'),
          // old_field 被刪除（不兼容）
          // 新增非空欄位無預設值（不兼容）
          TestDBColumn(name: 'required_field', dataType: 'VARCHAR', isNullable: false),
        ],
        indexes: [],
      );
      
      final issues = TestCompatibilityValidator.validateMigration(oldSchema, newSchema);
      expect(issues.length, greaterThanOrEqualTo(2));
    });
    
    test('API 回應兼容性', () {
      final oldResponse = {
        'id': 1,
        'species_name': '樟樹',
        'dbh_cm': 25.0,
      };
      
      final newResponse = {
        'id': 1,
        'species_name': '樟樹',
        'dbh_cm': 25.0,
        'is_placeholder': false,  // 新增欄位（兼容）
      };
      
      final issues = TestCompatibilityValidator.validateAPICompatibility(
        oldResponse, 
        newResponse,
      );
      expect(issues, isEmpty);
    });
  });
}
