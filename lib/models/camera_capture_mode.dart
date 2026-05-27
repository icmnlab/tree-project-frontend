/// 拍照／擷取模式（整合表單與現場流程共用）
enum CameraCaptureMode {
  /// 單純拍照，不啟動 DBH／樹種 AutoPilot
  plainPhoto,

  /// 整合拍照：DBH 視覺 + 樹種 + 拍照（ScannerPage 即時 YOLO 框）
  integrated,

  /// 一般相機拍照後僅樹種辨識
  photoWithSpecies,
}

extension CameraCaptureModeLabels on CameraCaptureMode {
  String get titleKey {
    switch (this) {
      case CameraCaptureMode.plainPhoto:
        return 'capture_plain';
      case CameraCaptureMode.integrated:
        return 'capture_integrated';
      case CameraCaptureMode.photoWithSpecies:
        return 'capture_species';
    }
  }

  String get subtitleKey => '${titleKey}_sub';
}
