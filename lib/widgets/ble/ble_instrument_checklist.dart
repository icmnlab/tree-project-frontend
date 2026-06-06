import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/locale_service.dart';

/// VLGEO2 現場連線前檢查清單（儀器設定 + 環境）。
class BleInstrumentChecklist {
  static const _prefsKey = 'ble_instrument_checklist_dismissed_v1';

  static Future<bool> isDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKey) ?? false;
  }

  static Future<void> setDismissed(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);
  }

  /// 若已勾選「不再顯示」則直接回傳 true；否則顯示對話框。
  static Future<bool> ensureAcknowledged(BuildContext context) async {
    if (await isDismissed()) return true;
    if (!context.mounted) return false;
    return show(context);
  }

  /// 回傳 true 表示使用者確認可開始掃描／連線。
  static Future<bool> show(BuildContext context) async {
    var dontShowAgain = false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.bluetooth, color: Colors.teal.shade700),
                  const SizedBox(width: 8),
                  Expanded(child: Text(ctx.tr('ble_checklist_title'))),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      ctx.tr('ble_checklist_intro'),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _CheckItem(
                      icon: Icons.memory_outlined,
                      text: ctx.tr('ble_checklist_mem_off'),
                    ),
                    _CheckItem(
                      icon: Icons.send_outlined,
                      text: ctx.tr('ble_checklist_send_not_files'),
                    ),
                    _CheckItem(
                      icon: Icons.apps_outage_outlined,
                      text: ctx.tr('ble_checklist_close_link'),
                    ),
                    _CheckItem(
                      icon: Icons.bluetooth_searching,
                      text: ctx.tr('ble_checklist_near_device'),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        ctx.tr('ble_checklist_dont_show'),
                        style: const TextStyle(fontSize: 13),
                      ),
                      value: dontShowAgain,
                      onChanged: (v) =>
                          setLocal(() => dontShowAgain = v ?? false),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(ctx.tr('cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(ctx.tr('ble_checklist_confirm')),
                ),
              ],
            );
          },
        );
      },
    );
    if (result == true && dontShowAgain) {
      await setDismissed(true);
    }
    return result == true;
  }
}

class _CheckItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _CheckItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.teal.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}
