import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../services/api_service.dart';
import '../services/admin_service.dart';
import 'api_key_management_screen.dart';

/// 系統狀態與維運設定（系統管理員）。
/// 整合：API 環境資訊、ML 服務狀態、資料庫備份觸發、API 金鑰管理入口。
/// 以 body widget 形式嵌入 AdminPage 內容區（不自帶 Scaffold）。
class SystemSettingsPage extends StatefulWidget {
  const SystemSettingsPage({super.key});

  @override
  State<SystemSettingsPage> createState() => _SystemSettingsPageState();
}

class _SystemSettingsPageState extends State<SystemSettingsPage> {
  final AdminService _adminService = AdminService();

  bool _loadingMl = false;
  bool? _mlConfigured;
  String? _mlUrl;
  String? _mlError;

  bool _isBackingUp = false;

  @override
  void initState() {
    super.initState();
    _fetchMlStatus();
  }

  Future<void> _fetchMlStatus() async {
    setState(() {
      _loadingMl = true;
      _mlError = null;
    });
    try {
      final resp = await ApiService.get('ml-service/status');
      if (!mounted) return;
      if (resp['success'] == true) {
        setState(() {
          _mlConfigured = resp['configured'] == true;
          _mlUrl = resp['ml_service_url']?.toString();
        });
      } else {
        setState(() => _mlError = resp['message']?.toString() ?? '無法取得 ML 服務狀態');
      }
    } catch (e) {
      if (mounted) setState(() => _mlError = '連線錯誤：$e');
    } finally {
      if (mounted) setState(() => _loadingMl = false);
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : Colors.green,
      ),
    );
  }

  Future<void> _backupDatabase() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('備份資料庫'),
        content: const Text('將在伺服器端匯出目前資料庫快照。確定要執行嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('開始備份'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isBackingUp = true);
    try {
      final resp = await _adminService.backupDatabase();
      if (resp['success'] == false) {
        _showSnack(resp['message']?.toString() ?? '備份失敗', error: true);
      } else {
        _showSnack(resp['message']?.toString() ?? '資料庫備份完成');
      }
    } catch (e) {
      _showSnack('備份發生錯誤：$e', error: true);
    } finally {
      if (mounted) setState(() => _isBackingUp = false);
    }
  }

  void _showRestoreInfo() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('還原資料庫'),
        content: const Text(
          '還原會覆蓋現有資料且無法復原，屬高風險操作。\n\n'
          '為安全起見，請於伺服器端由系統管理員手動執行還原流程（見 HANDOFF.md 的部署/備份章節），'
          '不在 App 內提供一鍵還原。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('了解'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = AppConfig();
    final envName = switch (appConfig.environment) {
      Environment.selfHosted => '自架伺服器',
    };
    final envIcon = switch (appConfig.environment) {
      Environment.selfHosted => Icons.dns,
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '系統狀態與維運',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
          const SizedBox(height: 16),

          // API 環境
          Card(
            elevation: 2,
            child: ListTile(
              leading: Icon(envIcon, color: Theme.of(context).colorScheme.primary),
              title: Text('API 環境：$envName'),
              subtitle: Text(appConfig.baseUrl),
            ),
          ),
          const SizedBox(height: 12),

          // ML 服務狀態
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.memory),
                      const SizedBox(width: 8),
                      Text('ML 服務狀態',
                          style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        tooltip: '重新檢查',
                        onPressed: _loadingMl ? null : _fetchMlStatus,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_loadingMl)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: LinearProgressIndicator(),
                    )
                  else if (_mlError != null)
                    Text(_mlError!, style: const TextStyle(color: Colors.red))
                  else
                    Row(
                      children: [
                        Icon(
                          _mlConfigured == true
                              ? Icons.check_circle
                              : Icons.error_outline,
                          color: _mlConfigured == true
                              ? Colors.green
                              : Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _mlConfigured == true
                                ? '已設定：${_mlUrl ?? '(未提供網址)'}'
                                : '未設定（由後端 .env 的 ML_SERVICE_URL 控制）',
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 資料庫備份 / 還原
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.backup_outlined),
                      const SizedBox(width: 8),
                      Text('資料庫備份',
                          style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text('定期備份可降低資料遺失風險。',
                      style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        icon: _isBackingUp
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.backup),
                        label: Text(_isBackingUp ? '備份中…' : '立即備份'),
                        onPressed: _isBackingUp ? null : _backupDatabase,
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.restore),
                        label: const Text('還原說明'),
                        onPressed: _showRestoreInfo,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // API 金鑰
          Card(
            elevation: 2,
            child: ListTile(
              leading: const Icon(Icons.key_outlined),
              title: const Text('API 金鑰管理'),
              subtitle: const Text('建立／檢視／撤銷供第三方存取的 API 金鑰'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ApiKeyManagementScreen(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
