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
      debugPrint('[TreeImageService] 載入索引失敗: $e');
      _imageIndex = {};
      _isIndexLoaded = true;
    }
  }

  /// 儲存影像索引
  Future<void> _saveIndex() async {
    try {
      final file = await _indexFile;
      final Map<String, dynamic> data = {};
      
      _imageIndex.forEach((treeId, images) {
        data[treeId] = images.map((img) => img.toJson()).toList();
      });
      
      await file.writeAsString(json.encode(data));
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
      
      // 建立縮圖（可選，這裡簡化處理）
      final thumbnailPath = '${treeDir.path}/${imageId}_thumb$extension';
      // TODO: 實作縮圖生成（使用 flutter_image_compress 套件）
      
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
  Future<bool> syncImage(TreeImage image) async {
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
      final response = await ApiService.post('/tree-images/upload', {
        'tree_id': image.treeId,
        'image_id': image.id,
        'type': image.type.name,
        'captured_at': image.capturedAt.toIso8601String(),
        'metadata': image.metadata,
        'image_data': base64Image,
      });

      if (response['success'] == true) {
        // 更新同步狀態
        final updatedImage = image.copyWith(
          isSynced: true,
          remotePath: response['remote_path'] as String?,
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

  /// 批次同步所有待同步照片
  Future<Map<String, dynamic>> syncAllPendingImages() async {
    final pendingImages = await getPendingSyncImages();
    
    int successCount = 0;
    int failCount = 0;
    
    for (final image in pendingImages) {
      final success = await syncImage(image);
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
}
