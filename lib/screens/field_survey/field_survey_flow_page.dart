import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../widgets/ble/ble_device_scanner.dart';
import '../ble_live_session_page.dart';
import '../pending_measurement_task_page.dart';
import '../../services/locale_service.dart';

/// 現場測量入口：集中 VLGEO2 連線、待測量與操作說明
class FieldSurveyFlowPage extends StatefulWidget {
  const FieldSurveyFlowPage({super.key});

  @override
  State<FieldSurveyFlowPage> createState() => _FieldSurveyFlowPageState();
}

class _FieldSurveyFlowPageState extends State<FieldSurveyFlowPage> {
  int _step = 0;
  BluetoothDevice? _selectedDevice;

  void _openBleLive() {
    if (_selectedDevice == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BleLiveSessionPage(initialDevice: _selectedDevice),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('field_survey_title')),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _step == 0 ? _buildMenu() : _buildBlePicker(),
        ),
      ),
    );
  }

  Widget _buildMenu() {
    return ListView(
      children: [
        const Text(
          '選擇現場作業類型',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'VLGEO2 建議關閉 ENABLE MEM，每棵按 SEND 後立即填寫整合表單。',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
        ),
        const SizedBox(height: 24),
        _FlowCard(
          icon: Icons.bluetooth_connected,
          title: 'VLGEO2 現場連線',
          subtitle: '掃描並選擇儀器 → 逐棵 SEND → 整合拍照表單',
          onTap: () => setState(() => _step = 1),
        ),
        const SizedBox(height: 12),
        _FlowCard(
          icon: Icons.assignment_outlined,
          title: '待測量任務',
          subtitle: '檢視並完成已上傳的待測量列',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const PendingMeasurementTaskPage(),
              ),
            );
          },
        ),
        const SizedBox(height: 24),
        ExpansionTile(
          title: Text(context.tr('capture_integrated')),
          children: [
            ListTile(
              dense: true,
              title: Text(context.tr('field_integrated_help')),
              subtitle: Text(context.tr('capture_integrated_sub')),
            ),
            ListTile(
              dense: true,
              title: Text(context.tr('field_survey_title')),
              subtitle: Text(context.tr('field_multi_user')),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBlePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => setState(() {
                _step = 0;
                _selectedDevice = null;
              }),
              icon: const Icon(Icons.arrow_back),
            ),
            Expanded(
              child: Text(
                context.tr('ble_pick_device'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: BleDeviceScanner(
            onDeviceSelected: (device) {
              setState(() => _selectedDevice = device);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已選：${device.platformName}')),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _selectedDevice == null ? null : _openBleLive,
          icon: const Icon(Icons.play_arrow),
          label: Text(context.tr('ble_start')),
        ),
      ],
    );
  }
}

class _FlowCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _FlowCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: 40, color: Colors.teal.shade700),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade700)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
