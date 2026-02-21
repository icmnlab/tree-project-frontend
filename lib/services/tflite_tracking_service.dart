import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:camera/camera.dart';

/// Bounding Box 結果
class TfliteBbox {
  final Rect rect; // 相對於預覽畫面的位置
  final double confidence;
  final String label;

  TfliteBbox(this.rect, this.confidence, this.label);
}

/// TensorFlow Lite 物件偵測與追蹤服務
///
/// 使用預先訓練好的 SSD MobileNet V1 模型進行邊緣推論
class TfliteObjectTrackingService {
  Interpreter? _interpreter;
  List<String>? _labels;
  bool _isInitialized = false;

  // 模型參數
  final int _inputSize = 300; // SSD MobileNet 通常吃 300x300
  final double _confidenceThreshold = 0.5;

  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      // 載入模型
      _interpreter = await Interpreter.fromAsset('assets/ml/mobilenet_ssd.tflite');
      
      // 載入標籤
      final labelData = await rootBundle.loadString('assets/ml/labels.txt');
      _labels = labelData.split('\n');

      _isInitialized = true;
      debugPrint('[TFLite] Initialization successful');
    } catch (e) {
      debugPrint('[TFLite] Error initializing: $e');
    }
  }

  void dispose() {
    _interpreter?.close();
    _isInitialized = false;
  }

  /// 從相機影像辨識物體
  List<TfliteBbox> processCameraImage(CameraImage image, int rotationDegrees) {
    if (!_isInitialized || _interpreter == null) return [];

    try {
      // 1. 將 CameraImage (YUV420 或 BGRA) 轉換為 RGB byte list
      final img.Image? decodedImage = _convertCameraImage(image);
      if (decodedImage == null) return [];

      // 2. 將影像縮放至模型所需大小 (300x300) 並進行預處理
      final img.Image resizedImage = img.copyResize(decodedImage, width: _inputSize, height: _inputSize);
      final inputBytes = _imageToByteListUint8(resizedImage, _inputSize);

      // 3. 準備輸出張量 (SSD MobileNet 輸出: [1, 10, 4] bounding boxes, [1, 10] classes, [1, 10] scores, [1] num detections)
      final outputLocations = List.generate(1, (_) => List.generate(10, (_) => List.filled(4, 0.0)));
      final outputClasses = List.generate(1, (_) => List.filled(10, 0.0));
      final outputScores = List.generate(1, (_) => List.filled(10, 0.0));
      final numDetections = List.filled(1, 0.0);

      Map<int, Object> outputs = {
        0: outputLocations,
        1: outputClasses,
        2: outputScores,
        3: numDetections,
      };

      // 4. 執行推論
      _interpreter!.runForMultipleInputs([inputBytes.buffer], outputs);

      // 5. 解析結果
      List<TfliteBbox> recognitions = [];
      int numberOfDetections = numDetections[0].toInt();

      // Original image dimensions (handling rotation)
      final double imgW = (rotationDegrees == 90 || rotationDegrees == 270) ? image.height.toDouble() : image.width.toDouble();
      final double imgH = (rotationDegrees == 90 || rotationDegrees == 270) ? image.width.toDouble() : image.height.toDouble();

      for (int i = 0; i < numberOfDetections; i++) {
        double score = outputScores[0][i];
        if (score > _confidenceThreshold) {
          int classId = outputClasses[0][i].toInt();
          String label = _labels != null && classId < _labels!.length ? _labels![classId] : 'Unknown';
          
          // 特別篩選: 樹木、植物、柱狀物相關標籤
          // Potted plant: 64
          if (classId != 64 && label.toLowerCase() != 'potted plant') {
              // 我們在此展示一個通用的 BBox 轉換
              // 如果要限制只抓樹，可以在此加上過濾條件
          }

          // SSD 輸出的是相對於影像寬高的比例 (ymin, xmin, ymax, xmax)
          double ymin = outputLocations[0][i][0];
          double xmin = outputLocations[0][i][1];
          double ymax = outputLocations[0][i][2];
          double xmax = outputLocations[0][i][3];

          // 轉換回原圖座標
          final rect = Rect.fromLTRB(
            xmin * imgW,
            ymin * imgH,
            xmax * imgW,
            ymax * imgH,
          );

          recognitions.add(TfliteBbox(rect, score, label));
        }
      }

      return recognitions;
    } catch (e) {
      debugPrint('[TFLite] Process error: $e');
      return [];
    }
  }

  /// 將影像轉換為輸入張量 (Uint8)
  Uint8List _imageToByteListUint8(img.Image image, int inputSize) {
    var convertedBytes = Uint8List(1 * inputSize * inputSize * 3);
    var buffer = ByteData.view(convertedBytes.buffer);
    int pixelIndex = 0;
    for (int i = 0; i < inputSize; i++) {
      for (int j = 0; j < inputSize; j++) {
        var pixel = image.getPixel(j, i);
        buffer.setUint8(pixelIndex++, pixel.r.toInt());
        buffer.setUint8(pixelIndex++, pixel.g.toInt());
        buffer.setUint8(pixelIndex++, pixel.b.toInt());
      }
    }
    return convertedBytes;
  }

  /// 簡易的 CameraImage 轉換 (支援 Android YUV420 和 iOS BGRA8888)
  img.Image? _convertCameraImage(CameraImage image) {
    try {
      if (image.format.group == ImageFormatGroup.bgra8888) {
        return img.Image.fromBytes(
          width: image.width,
          height: image.height,
          bytes: image.planes[0].bytes.buffer,
          order: img.ChannelOrder.bgra,
        );
      } else if (image.format.group == ImageFormatGroup.yuv420 || image.format.group == ImageFormatGroup.nv21) {
        // 將 YUV 轉為 RGB
        return _convertYUV420ToImage(image);
      }
    } catch (e) {
      debugPrint('[TFLite] Conversion error: $e');
    }
    return null;
  }

  img.Image _convertYUV420ToImage(CameraImage cameraImage) {
    final width = cameraImage.width;
    final height = cameraImage.height;

    final yRowStride = cameraImage.planes[0].bytesPerRow;
    final uvRowStride = cameraImage.planes[1].bytesPerRow;
    final uvPixelStride = cameraImage.planes[1].bytesPerPixel ?? 1;

    final image = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      int pY = y * yRowStride;
      int pUV = (y >> 1) * uvRowStride;

      for (int x = 0; x < width; x++) {
        final uvOffset = pUV + (x >> 1) * uvPixelStride;

        final yValue = cameraImage.planes[0].bytes[pY + x];
        final uValue = cameraImage.planes[1].bytes[uvOffset];
        final vValue = cameraImage.planes[2].bytes[uvOffset];

        int r = (yValue + 1.402 * (vValue - 128)).toInt();
        int g = (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128)).toInt();
        int b = (yValue + 1.772 * (uValue - 128)).toInt();

        image.setPixelRgb(x, y, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255));
      }
    }
    return image;
  }
}