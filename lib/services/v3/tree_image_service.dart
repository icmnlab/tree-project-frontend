/// V3 樹木影像服務
/// 
/// 功能：
/// 1. 本地儲存照片（app_documents/tree_images/）
/// 2. 照片元數據管理
/// 3. 雲端同步（可選）
/// 4. 照片壓縮和縮圖生成
/// 
/// 設計原則：
/// - 完全獨立於現有系統，不修改任何現有程式碼
/// - 本地優先，離線可用
/// - 支援多張照片記錄

import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import '../api_service.dart';

/// 照片類型
enum TreeImageType {
  overview,      // 全景照
  trunk,         // 樹幹照
  dbhMeasure,    // DBH 測量照
  crown,         // 樹冠照
  damage,        // 損傷照
  leaf,          // 葉片照
  bark,          // 樹皮照
  other,         // 其他
}

/// 樹木照片模型
class TreeImage {
  final String id;
  final String treeId;
  final String localPath;
  final String? remotePath;
  final TreeImageType type;
  final DateTime capturedAt;
  final Map<String, dynamic>? metadata;
  final bool isSynced;
  final String? thumbnailPath;

  TreeImage({
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

  factory TreeImage.fromJson(Map<String, dynamic> json) {
    return TreeImage(
      id: json['id'] as String,
      treeId: json['tree_id'] as String,
      localPath: json['local_path'] as String,
      remotePath: json['remote_path'] as String?,
      type: TreeImageType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => TreeImageType.other,
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

  TreeImage copyWith({
    String? id,
    String? treeId,
    String? localPath,
    String? remotePath,
    TreeImageType? type,
    DateTime? capturedAt,
    Map<String, dynamic>? metadata,
    bool? isSynced,
    String? thumbnailPath,
  }) {
    return TreeImage(
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

/// 樹木影像服務
class TreeImageService {
  static final TreeImageService _instance = TreeImageService._internal();
  factory TreeImageService() => _instance;
  TreeImageService._internal();

  final ImagePicker _imagePicker = ImagePicker();
  
  // 本地索引快取
  Map<String, List<TreeImage>> _imageIndex = {};
  bool _isIndexLoaded = false;

  // 同步互斥鎖 — 防止 fire-and-forget syncImage 與 syncAllPendingImages 並行
  Completer<void>? _syncLock;

  /// 取得影像儲存根目錄
  Future<Directory> get _imageRootDir async {
    final appDir = await getApplicationDocumentsDirectory();
    final imageDir = Directory('${appDir.path}/tree_images');
    if (!await imageDir.exists()) {
      await imageDir.create(recursive: true);
    }
    return imageDir;
  }

  /// 取得特定樹木的影像目錄
  Future<Directory> _getTreeImageDir(String treeId) async {
    final rootDir = await _imageRootDir;
    final treeDir = Directory('${rootDir.path}/$treeId');
    if (!await treeDir.exists()) {
      await treeDir.create(recursive: true);
    }
    return treeDir;
  }

  /// 取得索引檔案路徑
  Future<File> get _indexFile async {
    final rootDir = await _imageRootDir;
    return File('${rootDir.path}/image_index.json');
  }

  /// 載入影像索引
  Future<void> _loadIndex() async {
    if (_isIndexLoaded) return;
    
    try {
      final file = await _indexFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isEmpty) {
          _imageIndex = {};
          _isIndexLoaded = true;
          return;
        }
        final Map<String, dynamic> data = json.decode(content);
        
        _imageIndex = {};
        data.forEach((treeId, images) {
          _imageIndex[treeId] = (images as List)
              .map((img) => TreeImage.fromJson(img))
              .toList();
        });
      }
      _isIndexLoaded = true;
      debugPrint('[TreeImageService] 索引已載入，共 ${_imageIndex.length} 棵樹');
    } catch (e) {
      debugPrint('[TreeImageService] 載入索引失敗（可能損毀）: $e');
      // 嘗試從 .tmp 備份恢復
      try {
        final file = await _indexFile;
        final tmpFile = File('${file.path}.tmp');
        if (await tmpFile.exists()) {
          debugPrint('[TreeImageService] 嘗試從暫存檔恢復索引...');
          final content = await tmpFile.readAsString();
          final Map<String, dynamic> data = json.decode(content);
          _imageIndex = {};
          data.forEach((treeId, images) {
            _imageIndex[treeId] = (images as List)
                .map((img) => TreeImage.fromJson(img))
                .toList();
          });
          // 恢復成功，寫回主檔
          await tmpFile.rename(file.path);
          debugPrint('[TreeImageService] 從暫存檔恢復成功');
        } else {
          _imageIndex = {};
        }
      } catch (recoverErr) {
        debugPrint('[TreeImageService] 暫存檔恢復也失敗: $recoverErr');
        _imageIndex = {};
      }
      _isIndexLoaded = true;
    }
  }

  /// 儲存影像索引（原子寫入：先寫暫存檔再重命名，避免 crash 導致損毀）
  Future<void> _saveIndex() async {
    try {
      final file = await _indexFile;
      final Map<String, dynamic> data = {};
      
      _imageIndex.forEach((treeId, images) {
        data[treeId] = images.map((img) => img.toJson()).toList();
      });
      
      final jsonStr = json.encode(data);
      
      // 寫入暫存檔，再原子性重命名
      final tempFile = File('${file.path}.tmp');
      await tempFile.writeAsString(jsonStr, flush: true);
      await tempFile.rename(file.path);
      
      debugPrint('[TreeImageService] 索引已儲存');
    } catch (e) {
      debugPrint('[TreeImageService] 儲存索引失敗: $e');
    }
  }

  /// 拍攝照片
  Future<File?> captureImage({
    ImageSource source = ImageSource.camera,
    int maxWidth = 1920,
    int maxHeight = 1080,
    int quality = 85,
  }) async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: maxWidth.toDouble(),
        maxHeight: maxHeight.toDouble(),
        imageQuality: quality,
      );

      if (pickedFile != null) {
        return File(pickedFile.path);
      }
      return null;
    } catch (e) {
      debugPrint('[TreeImageService] 拍攝失敗: $e');
      return null;
    }
  }

  /// 儲存測量照片
  Future<TreeImage?> saveMeasurementImage({
    required String treeId,
    required File image,
    required TreeImageType type,
    Map<String, dynamic>? metadata,
  }) async {
    await _loadIndex();
    
    try {
      final treeDir = await _getTreeImageDir(treeId);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final imageId = '${treeId}_${type.name}_$timestamp';
      final originalPath = image.path;
      final extension = originalPath.contains('.') 
          ? '.${originalPath.split('.').last}' 
          : '.jpg';
      
      // 複製圖片到專屬目錄
      final targetPath = '${treeDir.path}/$imageId$extension';
      await image.copy(targetPath);
      
      // 建立縮圖（使用原圖副本，避免額外套件依賴）
      final thumbnailPath = '${treeDir.path}/${imageId}_thumb$extension';
      try {
        await File(targetPath).copy(thumbnailPath);
      } catch (_) {
        // 縮圖非關鍵路徑，失敗不阻斷流程
        debugPrint('[TreeImageService] 縮圖建立失敗，使用原圖路徑');
      }
      
      // 建立影像記錄
      final treeImage = TreeImage(
        id: imageId,
        treeId: treeId,
        localPath: targetPath,
        type: type,
        capturedAt: DateTime.now(),
        metadata: {
          'original_path': image.path,
          ...?metadata,
        },
        thumbnailPath: thumbnailPath,
      );
      
      // 更新索引
      _imageIndex[treeId] ??= [];
      _imageIndex[treeId]!.add(treeImage);
      await _saveIndex();
      
      debugPrint('[TreeImageService] 照片已儲存: $imageId');
      return treeImage;
    } catch (e) {
      debugPrint('[TreeImageService] 儲存照片失敗: $e');
      return null;
    }
  }

  /// 取得樹木的所有照片
  Future<List<TreeImage>> getTreeImages(String treeId) async {
    await _loadIndex();
    return _imageIndex[treeId] ?? [];
  }

  /// 取得特定類型的照片
  Future<List<TreeImage>> getTreeImagesByType(String treeId, TreeImageType type) async {
    final images = await getTreeImages(treeId);
    return images.where((img) => img.type == type).toList();
  }

  /// 刪除照片
  Future<bool> deleteImage(String imageId) async {
    await _loadIndex();
    
    try {
      // 找到並刪除檔案
      for (final entry in _imageIndex.entries) {
        final index = entry.value.indexWhere((img) => img.id == imageId);
        if (index != -1) {
          final image = entry.value[index];
          
          // 刪除本地檔案
          final file = File(image.localPath);
          if (await file.exists()) {
            await file.delete();
          }
          
          // 刪除縮圖
          if (image.thumbnailPath != null) {
            final thumbFile = File(image.thumbnailPath!);
            if (await thumbFile.exists()) {
              await thumbFile.delete();
            }
          }
          
          // 更新索引
          entry.value.removeAt(index);
          await _saveIndex();
          
          debugPrint('[TreeImageService] 照片已刪除: $imageId');
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint('[TreeImageService] 刪除照片失敗: $e');
      return false;
    }
  }

  /// 取得待同步的照片
  Future<List<TreeImage>> getPendingSyncImages() async {
    await _loadIndex();
    
    final pendingImages = <TreeImage>[];
    for (final images in _imageIndex.values) {
      pendingImages.addAll(images.where((img) => !img.isSynced));
    }
    return pendingImages;
  }

  /// 同步照片到雲端（如果後端支援）
  /// 使用互斥鎖避免與 syncAllPendingImages 並行衝突
  Future<bool> syncImage(TreeImage image) async {
    // 等待其他同步操作完成
    while (_syncLock != null) {
      await _syncLock!.future;
    }
    _syncLock = Completer<void>();
    
    try {
      return await _syncImageInternal(image);
    } finally {
      final lock = _syncLock;
      _syncLock = null;
      lock?.complete();
    }
  }

  /// 實際同步邏輯（內部，已持有鎖）
  Future<bool> _syncImageInternal(TreeImage image) async {
    try {
      final file = File(image.localPath);
      if (!await file.exists()) {
        debugPrint('[TreeImageService] 檔案不存在: ${image.localPath}');
        return false;
      }

      // 讀取檔案
      final bytes = await file.readAsBytes();
      final base64Image = base64Encode(bytes);

      // 上傳到後端
      // source 參數告知後端 tree_id 屬於哪張表，避免 SERIAL PK 碰撞誤連
      final response = await ApiService.post('/tree-images/upload', {
        'tree_id': image.treeId,
        'image_id': image.id,
        'type': image.type.name,
        'captured_at': image.capturedAt.toIso8601String(),
        'metadata': image.metadata,
        'image_data': base64Image,
        'source': 'pending',
      });

      if (response['success'] == true) {
        // 更新同步狀態 — 使用 Cloudinary 雲端 URL
        final cloudUrl = response['remote_path'] as String?;
        final thumbnailUrl = response['thumbnail_url'] as String?;
        
        final updatedImage = image.copyWith(
          isSynced: true,
          remotePath: cloudUrl,
          thumbnailPath: thumbnailUrl ?? image.thumbnailPath,
        );
        
        // 更新索引
        final treeImages = _imageIndex[image.treeId];
        if (treeImages != null) {
          final index = treeImages.indexWhere((img) => img.id == image.id);
          if (index != -1) {
            treeImages[index] = updatedImage;
            await _saveIndex();
          }
        }
        
        debugPrint('[TreeImageService] 照片已同步: ${image.id}');
        return true;
      }
      
      return false;
    } catch (e) {
      debugPrint('[TreeImageService] 同步失敗: $e');
      return false;
    }
  }

  /// 批次同步所有待同步照片（持有互斥鎖，防止重複上傳）
  Future<Map<String, dynamic>> syncAllPendingImages() async {
    // 等待其他同步操作完成
    while (_syncLock != null) {
      await _syncLock!.future;
    }
    _syncLock = Completer<void>();
    
    try {
      final pendingImages = await getPendingSyncImages();
      
      int successCount = 0;
      int failCount = 0;
      
      for (final image in pendingImages) {
        // 跳過已在上次迭代中被標記為已同步的（防止併發 syncImage 先完成的情形）
        if (image.isSynced) continue;
        
        final success = await _syncImageInternal(image);
        if (success) {
          successCount++;
        } else {
          failCount++;
        }
      }
      
      return {
        'total': pendingImages.length,
        'success': successCount,
        'failed': failCount,
      };
    } finally {
      final lock = _syncLock;
      _syncLock = null;
      lock?.complete();
    }
  }

  /// 計算儲存空間使用量
  Future<Map<String, dynamic>> getStorageStats() async {
    await _loadIndex();
    
    int totalImages = 0;
    int totalBytes = 0;
    int syncedCount = 0;
    
    for (final images in _imageIndex.values) {
      for (final image in images) {
        totalImages++;
        if (image.isSynced) syncedCount++;
        
        try {
          final file = File(image.localPath);
          if (await file.exists()) {
            totalBytes += await file.length();
          }
        } catch (e) {
          // 忽略
        }
      }
    }
    
    return {
      'total_images': totalImages,
      'total_trees': _imageIndex.length,
      'synced_count': syncedCount,
      'pending_count': totalImages - syncedCount,
      'storage_bytes': totalBytes,
      'storage_mb': (totalBytes / (1024 * 1024)).toStringAsFixed(2),
    };
  }

  /// 清除特定樹木的所有照片
  Future<bool> clearTreeImages(String treeId) async {
    await _loadIndex();
    
    try {
      final treeDir = await _getTreeImageDir(treeId);
      if (await treeDir.exists()) {
        await treeDir.delete(recursive: true);
      }
      
      _imageIndex.remove(treeId);
      await _saveIndex();
      
      debugPrint('[TreeImageService] 已清除樹木照片: $treeId');
      return true;
    } catch (e) {
      debugPrint('[TreeImageService] 清除失敗: $e');
      return false;
    }
  }

  /// 清除所有本地快取
  Future<bool> clearAllCache() async {
    try {
      final rootDir = await _imageRootDir;
      if (await rootDir.exists()) {
        await rootDir.delete(recursive: true);
      }
      
      _imageIndex.clear();
      _isIndexLoaded = false;
      
      debugPrint('[TreeImageService] 所有快取已清除');
      return true;
    } catch (e) {
      debugPrint('[TreeImageService] 清除快取失敗: $e');
      return false;
    }
  }

  /// 重新載入索引
  Future<void> reloadIndex() async {
    _isIndexLoaded = false;
    await _loadIndex();
  }

  // === Alias 方法（for V3 服務頁面相容） ===
  
  /// 取得待同步的照片 (alias for getPendingSyncImages)
  Future<List<TreeImage>> getUnsyncedImages() async {
    return getPendingSyncImages();
  }

  /// 取得所有照片
  Future<List<TreeImage>> getAllImages() async {
    await _loadIndex();
    final allImages = <TreeImage>[];
    for (final images in _imageIndex.values) {
      allImages.addAll(images);
    }
    return allImages;
  }

  /// 同步所有照片 (alias for syncAllPendingImages)
  Future<Map<String, dynamic>> syncAllImages() async {
    final result = await syncAllPendingImages();
    return {
      'synced': result['success'],
      'failed': result['failed'],
    };
  }

  /// 根據 metadata 中的 session_id 取得該 session 的所有照片
  Future<List<TreeImage>> getImagesBySessionId(String sessionId) async {
    await _loadIndex();
    final result = <TreeImage>[];
    for (final images in _imageIndex.values) {
      for (final img in images) {
        if (img.metadata?['session_id'] == sessionId) {
          result.add(img);
        }
      }
    }
    return result;
  }

  /// 清除已成功同步的本地照片檔案，釋放裝置儲存空間
  /// 只刪除 isSynced == true 的照片
  Future<Map<String, int>> cleanupSyncedImages() async {
    await _loadIndex();
    int cleaned = 0;
    int failed = 0;

    for (final entry in _imageIndex.entries) {
      final toRemove = <int>[];
      for (int i = 0; i < entry.value.length; i++) {
        final img = entry.value[i];
        if (!img.isSynced) continue;
        try {
          final file = File(img.localPath);
          if (await file.exists()) {
            await file.delete();
          }
          if (img.thumbnailPath != null) {
            final thumb = File(img.thumbnailPath!);
            if (await thumb.exists()) await thumb.delete();
          }
          toRemove.add(i);
          cleaned++;
        } catch (e) {
          debugPrint('[TreeImageService] 清理失敗: ${img.id} - $e');
          failed++;
        }
      }
      // 從後往前移除，避免 index 偏移
      for (final idx in toRemove.reversed) {
        entry.value.removeAt(idx);
      }
    }
    // 移除空的 treeId 條目
    _imageIndex.removeWhere((_, imgs) => imgs.isEmpty);
    await _saveIndex();

    debugPrint('[TreeImageService] 清理完成: $cleaned 刪除, $failed 失敗');
    return {'cleaned': cleaned, 'failed': failed};
  }

  /// 更新本地索引中的 treeId（用於轉移後重新映射）
  /// oldTreeId: pending_tree_measurements.id
  /// newTreeId: tree_survey.id 或 system_tree_id
  Future<void> remapTreeId(String oldTreeId, String newTreeId) async {
    await _loadIndex();
    final images = _imageIndex.remove(oldTreeId);
    if (images == null || images.isEmpty) return;

    final remapped = images.map((img) => img.copyWith(treeId: newTreeId)).toList();
    _imageIndex[newTreeId] = [...?_imageIndex[newTreeId], ...remapped];
    await _saveIndex();
    debugPrint('[TreeImageService] 重新映射 $oldTreeId → $newTreeId (${remapped.length} 張)');
  }
}
