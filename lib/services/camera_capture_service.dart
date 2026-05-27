import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/camera_capture_mode.dart';
import '../screens/scanner_page.dart';
import 'ar_measurement_service.dart';
import 'v3/tree_image_service.dart';

/// 拍照結果（各模式統一回傳）
class CameraCaptureResult {
  final File imageFile;
  final CameraCaptureMode mode;
  final MeasurementResult? measurement;

  const CameraCaptureResult({
    required this.imageFile,
    required this.mode,
    this.measurement,
  });
}

/// 依模式啟動對應相機／掃描流程
class CameraCaptureService {
  static final TreeImageService _imageService = TreeImageService();

  static Future<CameraCaptureResult?> capture(
    BuildContext context, {
    required CameraCaptureMode mode,
    ImageSource source = ImageSource.camera,
    double? initialDbh,
    String? speciesName,
  }) async {
    switch (mode) {
      case CameraCaptureMode.plainPhoto:
      case CameraCaptureMode.photoWithSpecies:
        final file = await _imageService.captureImage(source: source);
        if (file == null || !await file.exists()) return null;
        return CameraCaptureResult(imageFile: file, mode: mode);

      case CameraCaptureMode.integrated:
        final measurement = await Navigator.of(context).push<MeasurementResult>(
          MaterialPageRoute(
            builder: (_) => ScannerPage(
              initialDbh: initialDbh,
              speciesName: speciesName,
            ),
          ),
        );
        if (measurement?.capturedImagePath == null) return null;
        final path = measurement!.capturedImagePath!;
        final file = File(path);
        if (!await file.exists()) return null;
        return CameraCaptureResult(
          imageFile: file,
          mode: mode,
          measurement: measurement,
        );
    }
  }
}
