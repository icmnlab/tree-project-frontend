import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'tree_input_page.dart';
import 'constants/colors.dart';

class ScanQRCodePage extends StatefulWidget {
  const ScanQRCodePage({Key? key}) : super(key: key);

  @override
  State<ScanQRCodePage> createState() => _ScanQRCodePageState();
}

class _ScanQRCodePageState extends State<ScanQRCodePage> {
  MobileScannerController controller = MobileScannerController();
  bool isScanning = true;
  String qrCodeData = '';
  bool isProcessing = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (isProcessing || !isScanning) return;

    setState(() {
      isProcessing = true;
    });

    if (capture.barcodes.isNotEmpty) {
      final barcode = capture.barcodes.first;

      if (barcode.rawValue != null) {
        setState(() {
          qrCodeData = barcode.rawValue!;
          isScanning = false;
        });

        await _processQRCodeData(qrCodeData);
      }
    }

    setState(() {
      isProcessing = false;
    });
  }

  Future<void> _processQRCodeData(String data) async {
    try {
      // 解析QR碼資料
      Map<String, dynamic> qrData = jsonDecode(data);

      // 如果包含樹木資料，轉到TreeInputPage進行編輯
      if (qrData.containsKey('systemTreeController') &&
          qrData.containsKey('projectTreeController')) {
        String systemTree = qrData['systemTreeController'];
        String projectTree = qrData['projectTreeController'];

        // 顯示找到的資料
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已掃描到樹木資料: 系統編號=$systemTree, 專案編號=$projectTree'),
              duration: const Duration(seconds: 2),
            ),
          );

          // 導航至樹木輸入頁面
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TreeInputPage(
                treeData: {
                  '系統樹木': systemTree,
                  '專案樹木': projectTree,
                },
                isEdit: true,
              ),
            ),
          ).then((_) {
            // 返回時重新開始掃描
            if (mounted) {
              setState(() {
                isScanning = true;
                qrCodeData = '';
              });
            }
          });
        }
      } else {
        // QR碼不包含預期的資料
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('QR碼格式不正確'),
              duration: Duration(seconds: 2),
            ),
          );
          setState(() {
            isScanning = true;
          });
        }
      }
    } catch (e) {
      // 解析失敗
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('無法解析QR碼資料: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
        setState(() {
          isScanning = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('掃描樹木QR碼'),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.forestGreen, AppColors.leafGreen],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        elevation: 4,
      ),
      body: Column(
        children: [
          Expanded(
            flex: 5,
            child: isScanning
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      MobileScanner(
                        controller: controller,
                        onDetect: _onDetect,
                        startDelay: true,
                        fit: BoxFit.cover,
                      ),
                      CustomPaint(
                        painter: ScannerOverlay(),
                        child: const SizedBox(
                          width: 250,
                          height: 250,
                        ),
                      ),
                      Positioned(
                        bottom: 20,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            '請對準樹木QR碼',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [AppColors.leafGreen, AppColors.forestGreen],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.green.withOpacity(0.4),
                                  blurRadius: 20,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 60,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'QR碼掃描成功',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text('正在處理資料...'),
                          const SizedBox(height: 24),
                          if (isProcessing)
                            const CircularProgressIndicator(
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.green),
                            ),
                        ],
                      ),
                    ),
                  ),
          ),
          Expanded(
            flex: 1,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.grey.shade100, Colors.white],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    icon: ValueListenableBuilder(
                      valueListenable: controller.torchState,
                      builder: (context, state, child) {
                        switch (state) {
                          case TorchState.on:
                            return const Icon(Icons.flash_off);
                          case TorchState.off:
                            return const Icon(Icons.flash_on);
                        }
                      },
                    ),
                    label: const Text('閃光燈'),
                    onPressed: () => controller.toggleTorch(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  ElevatedButton.icon(
                    icon: ValueListenableBuilder(
                      valueListenable: controller.cameraFacingState,
                      builder: (context, state, child) {
                        switch (state) {
                          case CameraFacing.front:
                            return const Icon(Icons.camera_rear);
                          case CameraFacing.back:
                            return const Icon(Icons.camera_front);
                        }
                      },
                    ),
                    label: const Text('切換相機'),
                    onPressed: () => controller.switchCamera(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  if (!isScanning)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('重新掃描'),
                      onPressed: () {
                        setState(() {
                          isScanning = true;
                          qrCodeData = '';
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 自定義掃描區域外觀
class ScannerOverlay extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: 250,
      height: 250,
    );

    const lineColor = Colors.green;
    const cornerLength = 30.0;
    const strokeWidth = 4.0;

    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    // 繪製四個角落
    // 左上角
    canvas.drawLine(
        rect.topLeft, rect.topLeft + const Offset(cornerLength, 0), paint);
    canvas.drawLine(
        rect.topLeft, rect.topLeft + const Offset(0, cornerLength), paint);

    // 右上角
    canvas.drawLine(
        rect.topRight, rect.topRight + const Offset(-cornerLength, 0), paint);
    canvas.drawLine(
        rect.topRight, rect.topRight + const Offset(0, cornerLength), paint);

    // 左下角
    canvas.drawLine(rect.bottomLeft,
        rect.bottomLeft + const Offset(cornerLength, 0), paint);
    canvas.drawLine(rect.bottomLeft,
        rect.bottomLeft + const Offset(0, -cornerLength), paint);

    // 右下角
    canvas.drawLine(rect.bottomRight,
        rect.bottomRight + const Offset(-cornerLength, 0), paint);
    canvas.drawLine(rect.bottomRight,
        rect.bottomRight + const Offset(0, -cornerLength), paint);
  }

  @override
  bool shouldRepaint(ScannerOverlay oldDelegate) => false;
}
