import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';

class ApiKeyManagementScreen extends StatefulWidget {
  const ApiKeyManagementScreen({Key? key}) : super(key: key);

  @override
  _ApiKeyManagementScreenState createState() => _ApiKeyManagementScreenState();
}

class _ApiKeyManagementScreenState extends State<ApiKeyManagementScreen> {
  bool _isLoading = true;
  List<dynamic> _apiKeys = [];
  String? _error;

  final TextEditingController _nameController = TextEditingController();
  bool _isCreatingKey = false;
  String? _newApiKey;

  @override
  void initState() {
    super.initState();
    _fetchApiKeys();
  }

  Future<void> _fetchApiKeys() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await ApiService.get('admin/apikeys');

      if (response['success'] == true) {
        setState(() {
          _apiKeys = response['keys'] ?? [];
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = response['message'] ?? '無法載入 API 密鑰';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = '連接伺服器時發生錯誤';
        _isLoading = false;
      });
    }
  }

  Future<void> _createApiKey() async {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請輸入 API 密鑰名稱')),
      );
      return;
    }

    setState(() {
      _isCreatingKey = true;
      _newApiKey = null;
    });

    try {
      final response = await ApiService.post('admin/apikeys', {
        'name': _nameController.text,
        'permissions': ['read', 'write'],
      });

      if (response['success'] == true) {
        _nameController.clear();
        setState(() {
          _newApiKey = response['apiKey'];
          _isCreatingKey = false;
        });
        _fetchApiKeys();
      } else {
        setState(() {
          _isCreatingKey = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response['message'] ?? '創建 API 密鑰失敗')),
        );
      }
    } catch (e) {
      setState(() {
        _isCreatingKey = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('發生錯誤: $e')),
      );
    }
  }

  Future<void> _deleteApiKey(String id) async {
    try {
      final response = await ApiService.delete('admin/apikeys/$id');

      if (response['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('API 密鑰已刪除')),
        );
        _fetchApiKeys();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response['message'] ?? '刪除 API 密鑰失敗')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('發生錯誤: $e')),
      );
    }
  }

  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已複製到剪貼板')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('API 密鑰管理'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCreateKeyForm(),
                      const SizedBox(height: 24),
                      if (_newApiKey != null) _buildNewApiKeyCard(),
                      const SizedBox(height: 24),
                      Text(
                        'API 密鑰列表',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: _apiKeys.isEmpty
                            ? const Center(child: Text('暫無 API 密鑰'))
                            : ListView.builder(
                                itemCount: _apiKeys.length,
                                itemBuilder: (context, index) {
                                  final key = _apiKeys[index];
                                  return _buildApiKeyCard(key);
                                },
                              ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildCreateKeyForm() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '創建新的 API 密鑰',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '密鑰名稱',
                hintText: '例如：Flutter 應用',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isCreatingKey ? null : _createApiKey,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: _isCreatingKey
                    ? const CircularProgressIndicator()
                    : const Text('創建 API 密鑰'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewApiKeyCard() {
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.key, color: Colors.green.shade700),
                const SizedBox(width: 8),
                Text(
                  '新建的 API 密鑰',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: Colors.green.shade700),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '重要: 請立即複製此密鑰，離開此頁面後將無法再次查看',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _newApiKey!,
                style: const TextStyle(fontFamily: 'Courier'),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('複製'),
                onPressed: () => _copyToClipboard(_newApiKey!),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApiKeyCard(dynamic key) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        title: Text(key['name'] ?? '未命名密鑰'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ID: ${key['id']}'),
            Text('創建於: ${DateTime.parse(key['createdAt']).toLocal()}'),
            if (key['lastUsed'] != null)
              Text('最後使用: ${DateTime.parse(key['lastUsed']).toLocal()}'),
            Text('權限: ${(key['permissions'] as List).join(', ')}'),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete, color: Colors.red),
          onPressed: () => _deleteApiKey(key['id']),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
}
