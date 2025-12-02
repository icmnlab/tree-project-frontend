import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/species_identification_service.dart';

/// 樹種辨識頁面
/// 支援相機拍攝或從相簿選取圖片進行辨識
class SpeciesIdentificationPage extends StatefulWidget {
  const SpeciesIdentificationPage({super.key});

  @override
  State<SpeciesIdentificationPage> createState() => _SpeciesIdentificationPageState();
}

class _SpeciesIdentificationPageState extends State<SpeciesIdentificationPage> {
  final ImagePicker _picker = ImagePicker();
  
  Uint8List? _imageBytes;
  String _selectedOrgan = 'auto';
  bool _isLoading = false;
  Map<String, dynamic>? _result;
  String? _error;

  // 器官選項
  final List<Map<String, String>> _organOptions = [
    {'value': 'auto', 'label': '自動辨識', 'icon': '🌿'},
    {'value': 'leaf', 'label': '葉片', 'icon': '🍃'},
    {'value': 'flower', 'label': '花朵', 'icon': '🌸'},
    {'value': 'fruit', 'label': '果實', 'icon': '🍎'},
    {'value': 'bark', 'label': '樹皮', 'icon': '🪵'},
  ];

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      
      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _imageBytes = bytes;
          _result = null;
          _error = null;
        });
      }
    } catch (e) {
      setState(() {
        _error = '選取圖片失敗: $e';
      });
    }
  }

  Future<void> _identifySpecies() async {
    if (_imageBytes == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await SpeciesIdentificationService.identifyFromBytes(
        _imageBytes!,
        organ: _selectedOrgan,
      );

      setState(() {
        _result = result;
        _isLoading = false;
        if (!result['success']) {
          _error = result['error'] ?? '辨識失敗';
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = '辨識過程發生錯誤: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🌳 樹種辨識'),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showInfoDialog,
            tooltip: '服務說明',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 圖片顯示區
            _buildImageSection(),
            const SizedBox(height: 16),
            
            // 器官選擇
            _buildOrganSelector(),
            const SizedBox(height: 16),
            
            // 辨識按鈕
            _buildIdentifyButton(),
            const SizedBox(height: 16),
            
            // 錯誤訊息
            if (_error != null) _buildErrorCard(),
            
            // 結果顯示
            if (_result != null && _result!['success'] == true) _buildResultSection(),
          ],
        ),
      ),
      floatingActionButton: _buildFAB(),
    );
  }

  Widget _buildImageSection() {
    return Card(
      elevation: 4,
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: _imageBytes != null
            ? Image.memory(
                _imageBytes!,
                fit: BoxFit.cover,
              )
            : Container(
                color: Colors.grey.shade200,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_photo_alternate,
                      size: 64,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '請選擇或拍攝植物照片',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _pickImage(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('拍照'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton.icon(
                          onPressed: () => _pickImage(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library),
                          label: const Text('相簿'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildOrganSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '選擇拍攝部位（可提高辨識準確度）',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _organOptions.map((option) {
                final isSelected = _selectedOrgan == option['value'];
                return ChoiceChip(
                  label: Text('${option['icon']} ${option['label']}'),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _selectedOrgan = option['value']!;
                      });
                    }
                  },
                  selectedColor: Colors.green.shade200,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdentifyButton() {
    return ElevatedButton(
      onPressed: _imageBytes != null && !_isLoading ? _identifySpecies : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: _isLoading
          ? const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 12),
                Text('辨識中...'),
              ],
            )
          : const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search),
                SizedBox(width: 8),
                Text('開始辨識', style: TextStyle(fontSize: 16)),
              ],
            ),
    );
  }

  Widget _buildErrorCard() {
    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade700),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _error!,
                style: TextStyle(color: Colors.red.shade700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultSection() {
    final primaryResult = _result!['primaryResult'];
    final allResults = _result!['allResults'] as List? ?? [];
    final gbifData = _result!['gbifData'];
    final localMatch = _result!['localMatch'];
    final remainingRequests = _result!['remainingRequests'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 剩餘次數提示
        if (remainingRequests != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '今日剩餘辨識次數: $remainingRequests',
              style: TextStyle(
                color: remainingRequests < 50 ? Colors.orange : Colors.grey,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ),

        // 主要結果
        if (primaryResult != null) _buildPrimaryResultCard(primaryResult),
        
        // 本地資料庫匹配
        if (localMatch != null) _buildLocalMatchCard(localMatch),
        
        // GBIF 驗證資訊
        if (gbifData != null) _buildGBIFCard(gbifData),
        
        // 其他可能結果
        if (allResults.length > 1) ...[
          const SizedBox(height: 16),
          const Text(
            '其他可能的物種',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          ...allResults.skip(1).take(4).map((r) => _buildAlternativeResult(r)),
        ],
      ],
    );
  }

  Widget _buildPrimaryResultCard(Map<String, dynamic> result) {
    final score = (result['score'] as num?)?.toDouble() ?? 0.0;
    final scorePercent = (score * 100).toStringAsFixed(1);
    final scientificName = result['scientificName'] ?? '未知';
    final commonNames = (result['commonNames'] as List?)?.cast<String>() ?? [];
    final family = result['family'] ?? '';
    final images = (result['images'] as List?) ?? [];

    return Card(
      elevation: 4,
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 28),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '辨識結果',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getScoreColor(score),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '$scorePercent%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // 學名
            Text(
              scientificName,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                fontStyle: FontStyle.italic,
              ),
            ),
            
            // 常用名
            if (commonNames.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                commonNames.take(3).join('、'),
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
            
            // 科別
            if (family.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.category, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text('科別: $family', style: const TextStyle(color: Colors.grey)),
                ],
              ),
            ],
            
            // 參考圖片
            if (images.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 80,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: images.length,
                  itemBuilder: (context, index) {
                    final img = images[index];
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          img['url'] ?? '',
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 80,
                            height: 80,
                            color: Colors.grey.shade300,
                            child: const Icon(Icons.broken_image),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLocalMatchCard(Map<String, dynamic> match) {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.eco, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                const Text(
                  '本地資料庫匹配',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            _buildInfoRow('名稱', match['name'] ?? ''),
            _buildInfoRow('碳匯效率', '${match['carbonEfficiency'] ?? 0} kg CO₂/年'),
            _buildInfoRow('適合土壤', match['soilType'] ?? ''),
            _buildInfoRow('日照需求', match['sunExposure'] ?? ''),
            _buildInfoRow('適合區域', (match['suitableRegions'] as List?)?.join('、') ?? ''),
            if (match['description'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  match['description'],
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGBIFCard(Map<String, dynamic> data) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.verified, color: Colors.green),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'GBIF 學術驗證',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (data['taiwanOccurrences'] != null)
                  Chip(
                    label: Text('台灣紀錄: ${data['taiwanOccurrences']}'),
                    backgroundColor: Colors.green.shade100,
                    labelStyle: const TextStyle(fontSize: 12),
                  ),
              ],
            ),
            const Divider(),
            _buildInfoRow('完整學名', data['scientificName'] ?? ''),
            _buildInfoRow('界', data['kingdom'] ?? ''),
            _buildInfoRow('門', data['phylum'] ?? ''),
            _buildInfoRow('綱', data['class'] ?? ''),
            _buildInfoRow('目', data['order'] ?? ''),
            _buildInfoRow('科', data['family'] ?? ''),
            if (data['gbifUrl'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextButton.icon(
                  onPressed: () {
                    // TODO: 開啟 GBIF 連結
                  },
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('在 GBIF 查看更多'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlternativeResult(Map<String, dynamic> result) {
    final score = (result['score'] as num?)?.toDouble() ?? 0.0;
    final scorePercent = (score * 100).toStringAsFixed(1);
    final scientificName = result['scientificName'] ?? '未知';
    final commonNames = (result['commonNames'] as List?)?.cast<String>() ?? [];

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getScoreColor(score),
          child: Text(
            '$scorePercent%',
            style: const TextStyle(color: Colors.white, fontSize: 10),
          ),
        ),
        title: Text(
          scientificName,
          style: const TextStyle(fontStyle: FontStyle.italic),
        ),
        subtitle: commonNames.isNotEmpty
            ? Text(commonNames.take(2).join('、'))
            : null,
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Color _getScoreColor(double score) {
    if (score >= 0.8) return Colors.green;
    if (score >= 0.5) return Colors.orange;
    return Colors.red;
  }

  Widget? _buildFAB() {
    if (_imageBytes == null) return null;
    
    return FloatingActionButton(
      onPressed: () {
        showModalBottomSheet(
          context: context,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.camera_alt),
                  title: const Text('拍攝新照片'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('從相簿選擇'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
      backgroundColor: Colors.green.shade700,
      child: const Icon(Icons.add_a_photo, color: Colors.white),
    );
  }

  void _showInfoDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info, color: Colors.green),
            SizedBox(width: 8),
            Text('服務說明'),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '資料來源',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('• Pl@ntNet - 法國國家研究機構開發，可辨識 78,000+ 植物物種'),
              SizedBox(height: 4),
              Text('• GBIF - 全球生物多樣性資訊機構，提供學術驗證'),
              SizedBox(height: 4),
              Text('• iNaturalist - 公民科學平台，提供觀察紀錄'),
              SizedBox(height: 16),
              Text(
                '使用建議',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('• 拍攝清晰、光線充足的照片'),
              Text('• 選擇正確的器官類型可提高準確度'),
              Text('• 葉片和花朵通常辨識效果最好'),
              Text('• 可信度越高，結果越可靠'),
              SizedBox(height: 16),
              Text(
                '免費額度',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('每日可免費辨識 500 次'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('了解'),
          ),
        ],
      ),
    );
  }
}
