// [T6][S1] 樂觀鎖衝突對話框 — 三選一
// 後端 updateTreeV2 在 expected_updated_at 不符時回 409 + serverVersion；
// 前端跳此對話框讓使用者選擇處理方式。

import 'package:flutter/material.dart';

enum ConflictAction {
  /// 強制覆寫：用我的版本蓋過伺服器（重送但不帶 expected_updated_at）
  keepMine,

  /// 用伺服器版本：丟棄本地編輯，回到列表（呼叫端 pop 即可）
  useServer,

  /// 手動合併：把伺服器最新值載回表單，使用者重新編輯
  manualMerge,
}

/// 顯示「資料已被其他人修改」對話框並回傳使用者選擇。
/// [serverVersion] 後端回傳的最新一筆 row（用於 diff 顯示）
/// [myDraft] 使用者目前正在編輯的資料（用於 diff 顯示）
Future<ConflictAction?> showConflictResolutionDialog(
  BuildContext context, {
  required Map<String, dynamic> serverVersion,
  required Map<String, dynamic> myDraft,
}) {
  final diffs = _computeDiffs(serverVersion, myDraft);
  return showDialog<ConflictAction>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange),
          SizedBox(width: 8),
          Expanded(child: Text('資料已被他人修改')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('在你編輯的同時，這筆資料已被另一位使用者修改並儲存。'),
            const SizedBox(height: 12),
            if (diffs.isNotEmpty) ...[
              const Text('差異欄位：',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              ...diffs.map((d) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• ${d.field}',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('  伺服器：${d.server}',
                            style: const TextStyle(color: Colors.blue)),
                        Text('  我的：${d.mine}',
                            style: const TextStyle(color: Colors.green)),
                      ],
                    ),
                  )),
              const SizedBox(height: 12),
            ],
            const Text('請選擇處理方式：',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, ConflictAction.useServer),
          child: const Text('用伺服器版（捨棄我的）'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, ConflictAction.manualMerge),
          child: const Text('手動合併'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ConflictAction.keepMine),
          child: const Text('強制覆寫'),
        ),
      ],
    ),
  );
}

class _Diff {
  final String field;
  final String server;
  final String mine;
  _Diff(this.field, this.server, this.mine);
}

List<_Diff> _computeDiffs(
    Map<String, dynamic> server, Map<String, dynamic> mine) {
  // 只比 mine 有送的欄位（避免列出整個 server row 一堆無關欄位）
  // 跳過控制欄位
  const skip = {'id', 'updated_at', 'created_at', 'expected_updated_at'};
  final out = <_Diff>[];
  for (final entry in mine.entries) {
    if (skip.contains(entry.key)) continue;
    final s = server[entry.key];
    final m = entry.value;
    if (_normalize(s) != _normalize(m)) {
      out.add(_Diff(entry.key, '${s ?? '(空)'}', '${m ?? '(空)'}'));
    }
  }
  return out;
}

String _normalize(dynamic v) {
  if (v == null) return '';
  if (v is num) return v.toString();
  return v.toString().trim();
}
