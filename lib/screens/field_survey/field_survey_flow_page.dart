import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../widgets/ble/ble_device_scanner.dart';
import '../../widgets/field/field_session_setup.dart';
import '../ble_live_session_page.dart';
import '../pending_measurement_task_page.dart';
import '../../services/locale_service.dart';

/// 現場測量入口：集中 VLGEO2 連線、待測量與操作說明
class FieldSurveyFlowPage extends StatefulWidget {
  /// 從 BLE 匯入頁捷徑進入時，直接開啟裝置選擇步驟
  final bool openBleDeviceStep;

  const FieldSurveyFlowPage({super.key, this.openBleDeviceStep = false});

  @override
  State<FieldSurveyFlowPage> createState() => _FieldSurveyFlowPageState();
}

class _FieldSurveyFlowPageState extends State<FieldSurveyFlowPage> {
  late int _step;
  BluetoothDevice? _selectedDevice;
  FieldSessionSetup? _sessionSetup;

  @override
  void initState() {
    super.initState();
    _step = widget.openBleDeviceStep ? 1 : 0;
  }

  Future<void> _openBleLive() async {
    if (_selectedDevice == null) return;

    final setup = _sessionSetup ??
        await showFieldSessionSetupDialog(context);
    if (setup == null || !mounted) return;

    setState(() => _sessionSetup = setup);

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BleLiveSessionPage(
          initialDevice: _selectedDevice,
          initialSessionSetup: setup,
        ),
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
        Text(
          context.tr('field_survey_pick'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          context.tr('field_survey_ble_hint'),
          style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
        ),
        const SizedBox(height: 24),
        _FlowCard(
          icon: Icons.bluetooth_connected,
          title: context.tr('field_ble_title'),
          subtitle: context.tr('field_ble_sub'),
          onTap: () => setState(() => _step = 1),
        ),
        const SizedBox(height: 12),
        _FlowCard(
          icon: Icons.assignment_outlined,
          title: context.tr('field_pending_title'),
          subtitle: context.tr('field_pending_sub'),
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
        if (_sessionSetup != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${_sessionSetup!.projectName} · ${_sessionSetup!.projectArea}',
              style: TextStyle(fontSize: 12, color: Colors.teal.shade700),
            ),
          ),
        TextButton.icon(
          onPressed: () async {
            final s = await showFieldSessionSetupDialog(
              context,
              initial: _sessionSetup,
            );
            if (s != null && mounted) setState(() => _sessionSetup = s);
          },
          icon: const Icon(Icons.edit_location_alt, size: 18),
          label: Text(context.tr('field_setup_title')),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: BleDeviceScanner(
            onDeviceSelected: (device) {
              setState(() => _selectedDevice = device);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${device.platformName}')),
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
