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
  final ScrollController _scrollController = ScrollController();
  
  Uint8List? _imageBytes;
  String _selectedOrgan = 'auto';
  bool _isLoading = false;
  Map<String, dynamic>? _result;
  String? _error;

  // 器官選項
  final List<Map<String, String>> _organOptions = [
    {'value': 'auto', 'label': '自動', 'icon': '🔍'},
    {'value': 'leaf', 'label': '葉片', 'icon': '🍃'},
    {'value': 'flower', 'label': '花朵', 'icon': '🌸'},
    {'value': 'fruit', 'label': '果實', 'icon': '🍎'},
    {'value': 'bark', 'label': '樹皮', 'icon': '🪵'},
  ];

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

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
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🌿 ', style: TextStyle(fontSize: 24)),
            Text('植物鑑定'),
          ],
        ),
        centerTitle: true,
        backgroundColor: Colors.green.shade600,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: _showInfoDialog,
            tooltip: '使用說明',
          ),
        ],
      ),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 圖片顯示區
                  _buildImageSection(),
                  const SizedBox(height: 20),
                  
                  // 器官選擇
                  _buildOrganSelector(),
                  const SizedBox(height: 20),
                  
                  // 辨識按鈕
                  _buildIdentifyButton(),
                  const SizedBox(height: 16),
                  
                  // 錯誤訊息
                  if (_error != null) _buildErrorCard(),
                  
                  // 結果顯示
                  if (_result != null && _result!['success'] == true) _buildResultSection(),
                  
                  // 底部留白，確保可以滾動到底
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
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
    final canIdentify = _imageBytes != null && !_isLoading;
    
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: canIdentify 
            ? LinearGradient(
                colors: [Colors.green.shade600, Colors.teal.shade600],
              )
            : null,
        color: canIdentify ? null : Colors.grey.shade300,
        boxShadow: canIdentify ? [
          BoxShadow(
            color: Colors.green.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ] : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: canIdentify ? _identifySpecies : null,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: _isLoading
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Text(
                        '智慧辨識中...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        color: canIdentify ? Colors.white : Colors.grey.shade500,
                        size: 24,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '開始辨識',
                        style: TextStyle(
                          color: canIdentify ? Colors.white : Colors.grey.shade500,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: Colors.red.shade600, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _error!,
              style: TextStyle(color: Colors.red.shade700, fontSize: 14),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: Colors.red.shade400, size: 20),
            onPressed: () => setState(() => _error = null),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
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
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: remainingRequests < 50 
                  ? Colors.orange.shade50 
                  : Colors.green.shade50,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  remainingRequests < 50 ? Icons.warning_amber : Icons.check_circle_outline,
                  size: 16,
                  color: remainingRequests < 50 ? Colors.orange : Colors.green,
                ),
                const SizedBox(width: 6),
                Text(
                  '今日剩餘 $remainingRequests 次辨識',
                  style: TextStyle(
                    color: remainingRequests < 50 ? Colors.orange.shade700 : Colors.green.shade700,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

        // 主要結果
        if (primaryResult != null) _buildPrimaryResultCard(primaryResult),
        
        // 本地資料庫匹配
        if (localMatch != null) ...[
          const SizedBox(height: 16),
          _buildLocalMatchCard(localMatch),
        ],
        
        // GBIF 驗證資訊
        if (gbifData != null) ...[
          const SizedBox(height: 16),
          _buildGBIFCard(gbifData),
        ],
        
        // 其他可能結果
        if (allResults.length > 1) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              Icon(Icons.format_list_bulleted, color: Colors.grey.shade600, size: 18),
              const SizedBox(width: 8),
              Text(
                '其他可能物種',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
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

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.green.shade50, Colors.teal.shade50],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        children: [
          // 標題區
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.shade600,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(19)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.eco, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    '辨識結果',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getScoreIcon(score),
                        size: 16,
                        color: _getScoreColor(score),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$scorePercent%',
                        style: TextStyle(
                          color: _getScoreColor(score),
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // 內容區
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 學名
                Text(
                  scientificName,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    fontStyle: FontStyle.italic,
                    color: Colors.green.shade800,
                  ),
                ),
                
                // 常用名
                if (commonNames.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    commonNames.take(3).join(' · '),
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
                
                // 科別
                if (family.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.category_outlined, size: 14, color: Colors.green.shade700),
                        const SizedBox(width: 6),
                        Text(
                          family,
                          style: TextStyle(
                            color: Colors.green.shade700,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                
                // 參考圖片
                if (images.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 90,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: images.length,
                      itemBuilder: (context, index) {
                        final img = images[index];
                        return Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              img['url'] ?? '',
                              width: 90,
                              height: 90,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 90,
                                height: 90,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(Icons.broken_image, color: Colors.grey.shade400),
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
        ],
      ),
    );
  }

  IconData _getScoreIcon(double score) {
    if (score >= 0.8) return Icons.verified;
    if (score >= 0.5) return Icons.help_outline;
    return Icons.warning_amber;
  }

  Widget _buildLocalMatchCard(Map<String, dynamic> match) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.eco, color: Colors.blue.shade700, size: 18),
                ),
                const SizedBox(width: 10),
                Text(
                  '本地資料庫匹配',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.blue.shade800,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _buildInfoRow('名稱', match['name'] ?? ''),
                _buildInfoRow('碳匯效率', '${match['carbonEfficiency'] ?? 0} kg CO₂/年'),
                _buildInfoRow('適合土壤', match['soilType'] ?? ''),
                _buildInfoRow('日照需求', match['sunExposure'] ?? ''),
                _buildInfoRow('適合區域', (match['suitableRegions'] as List?)?.join('、') ?? ''),
                if (match['description'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      match['description'],
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGBIFCard(Map<String, dynamic> data) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.verified_outlined, color: Colors.green.shade700, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'GBIF 學術驗證',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.green.shade800,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (data['taiwanOccurrences'] != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.shade600,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '台灣 ${data['taiwanOccurrences']} 筆',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _buildInfoRow('完整學名', data['scientificName'] ?? ''),
                _buildInfoRow('界', data['kingdom'] ?? ''),
                _buildInfoRow('門', data['phylum'] ?? ''),
                _buildInfoRow('綱', data['class'] ?? ''),
                _buildInfoRow('目', data['order'] ?? ''),
                _buildInfoRow('科', data['family'] ?? ''),
                if (data['gbifUrl'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: TextButton.icon(
                      onPressed: () {
                        // TODO: 開啟 GBIF 連結
                      },
                      icon: Icon(Icons.open_in_new, size: 16, color: Colors.green.shade600),
                      label: Text(
                        '在 GBIF 查看更多',
                        style: TextStyle(color: Colors.green.shade600),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlternativeResult(Map<String, dynamic> result) {
    final score = (result['score'] as num?)?.toDouble() ?? 0.0;
    final scorePercent = (score * 100).toStringAsFixed(1);
    final scientificName = result['scientificName'] ?? '未知';
    final commonNames = (result['commonNames'] as List?)?.cast<String>() ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: _getScoreColor(score).withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: _getScoreColor(score).withOpacity(0.3)),
          ),
          child: Center(
            child: Text(
              '$scorePercent%',
              style: TextStyle(
                color: _getScoreColor(score),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        title: Text(
          scientificName,
          style: TextStyle(
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade800,
          ),
        ),
        subtitle: commonNames.isNotEmpty
            ? Text(
                commonNames.take(2).join(' · '),
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              )
            : null,
        trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getScoreColor(double score) {
    if (score >= 0.8) return Colors.green.shade600;
    if (score >= 0.5) return Colors.orange.shade600;
    return Colors.red.shade600;
  }

  Widget? _buildFAB() {
    if (_imageBytes == null) return null;
    
    return FloatingActionButton.extended(
      onPressed: () {
        showModalBottomSheet(
          context: context,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (context) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.camera_alt, color: Colors.green.shade600),
                    ),
                    title: const Text('拍攝新照片'),
                    subtitle: const Text('使用相機即時拍攝', style: TextStyle(fontSize: 12)),
                    onTap: () {
                      Navigator.pop(context);
                      _pickImage(ImageSource.camera);
                    },
                  ),
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.photo_library, color: Colors.teal.shade600),
                    ),
                    title: const Text('從相簿選擇'),
                    subtitle: const Text('選擇現有照片', style: TextStyle(fontSize: 12)),
                    onTap: () {
                      Navigator.pop(context);
                      _pickImage(ImageSource.gallery);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
      backgroundColor: Colors.green.shade600,
      icon: const Icon(Icons.add_a_photo, color: Colors.white),
      label: const Text('更換圖片', style: TextStyle(color: Colors.white)),
    );
  }

  void _showInfoDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.eco, color: Colors.green.shade600, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      '植物鑑定說明',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildInfoSection(
                icon: Icons.storage,
                title: '資料來源',
                items: [
                  'Pl@ntNet - 可辨識 78,000+ 植物',
                  'GBIF - 全球生物多樣性學術驗證',
                  'iNaturalist - 公民科學觀察紀錄',
                ],
              ),
              const SizedBox(height: 16),
              _buildInfoSection(
                icon: Icons.tips_and_updates,
                title: '拍攝建議',
                items: [
                  '選擇光線充足的環境',
                  '拍攝清晰特寫照片',
                  '葉片和花朵辨識效果最佳',
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.card_giftcard, color: Colors.green.shade600),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        '每日免費辨識 500 次',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoSection({
    required IconData icon,
    required String title,
    required List<String> items,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: Colors.grey.shade600),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...items.map((item) => Padding(
          padding: const EdgeInsets.only(left: 26, bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('• ', style: TextStyle(color: Colors.grey.shade500)),
              Expanded(
                child: Text(
                  item,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                ),
              ),
            ],
          ),
        )),
      ],
    );
  }
}
