// lib/admin_research_dataset_page.dart
//
// 「研究資料蒐集」管理員頁
// ----------------------------------
// 用途：管理員拿著捲尺到野外，量「樹幹周長 + 拍攝距離」+ 拍 1~3 張手機照，
//      上傳作為 DBH 距離校正/評估用的乾淨資料集。
//
// Backend：POST/GET/DELETE /api/admin/research-dataset
//          GET /api/admin/research-dataset/export.csv （可由電腦端 curl）
//
// 設計重點：
//   - 表單只要 4 個必填：樹編號 / 周長(cm) / 距離(m) / 至少 1 張照片
//   - 周長 → DBH 由後端 generated column 算出，避免 (人為) 除 π 的精度誤差
//   - 手機型號 + GPS 自動填，不要逼使用者打字
//   - 列表可看到歷史紀錄，可一鍵刪除（刪 DB row，Cloudinary 圖暫不刪）

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:exif/exif.dart';

import 'services/api_service.dart';

class AdminResearchDatasetPage extends StatefulWidget {
  const AdminResearchDatasetPage({super.key});

  @override
  State<AdminResearchDatasetPage> createState() =>
      _AdminResearchDatasetPageState();
}

class _AdminResearchDatasetPageState extends State<AdminResearchDatasetPage> {
  final _formKey = GlobalKey<FormState>();
  final _treeIdCtrl = TextEditingController();
  final _circCtrl = TextEditingController();
  final _distCtrl = TextEditingController();
  final _speciesCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  final List<XFile> _photos = []; // 1~3 張主照
  XFile? _evidence; // 證據照（捲尺貼樹）

  String? _phoneModel;
  double? _gpsLat;
  double? _gpsLng;

  bool _submitting = false;
  bool _loadingList = false;
  List<Map<String, dynamic>> _entries = [];

  @override
  void initState() {
    super.initState();
    _autoFillPhone();
    _autoFillGps();
    _fetchList();
  }

  @override
  void dispose() {
    _treeIdCtrl.dispose();
    _circCtrl.dispose();
    _distCtrl.dispose();
    _speciesCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // ─────────────── 自動填欄 ───────────────

  Future<void> _autoFillPhone() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        _phoneModel = '${info.manufacturer} ${info.model}';
      } else if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        _phoneModel = '${info.utsname.machine} ${info.systemVersion}';
      } else {
        _phoneModel = Platform.operatingSystem;
      }
      if (mounted) setState(() {});
    } catch (_) {
      _phoneModel = null;
    }
  }

  Future<void> _autoFillGps() async {
    try {
      final ok = await Geolocator.isLocationServiceEnabled();
      if (!ok) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      _gpsLat = pos.latitude;
      _gpsLng = pos.longitude;
      if (mounted) setState(() {});
    } catch (_) {
      // 拿不到就算了，讓欄位留空
    }
  }

  // ─────────────── 拍/選照片 ───────────────

  Future<void> _addPhoto({required bool isEvidence}) async {
    if (!isEvidence && _photos.length >= 3) {
      _toast('最多 3 張主照');
      return;
    }
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: const Text('拍照'),
            onTap: () => Navigator.pop(context, 'camera'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('從相簿選'),
            onTap: () => Navigator.pop(context, 'gallery'),
          ),
        ]),
      ),
    );
    if (action == null) return;
    final XFile? picked = await _picker.pickImage(
      source: action == 'camera' ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 2048,
      imageQuality: 88,
    );
    if (picked == null) return;
    setState(() {
      if (isEvidence) {
        _evidence = picked;
      } else {
        _photos.add(picked);
      }
    });
  }

  void _removePhoto(int idx) {
    setState(() => _photos.removeAt(idx));
  }

  void _removeEvidence() {
    setState(() => _evidence = null);
  }

  // ─────────────── 提交 ───────────────

  Future<String> _toBase64(XFile f) async {
    final bytes = await f.readAsBytes();
    return base64Encode(bytes);
  }

  /// 嘗試從第一張主照 EXIF 推焦距 (px)，
  /// 失敗就回 null（後端容許 null）。
  Future<({double? focalPx, int? w, int? h})> _extractFocal(XFile f) async {
    try {
      final bytes = await f.readAsBytes();
      final tags = await readExifFromBytes(bytes);
      final w = _exifInt(tags, 'EXIF ExifImageWidth') ??
          _exifInt(tags, 'Image ImageWidth');
      final h = _exifInt(tags, 'EXIF ExifImageLength') ??
          _exifInt(tags, 'Image ImageLength');
      final f35 = _exifNum(tags, 'EXIF FocalLengthIn35mmFilm');
      // 35mm 等效焦距 → 像素焦距：fx_px ≈ f35 * (image_width / 36.0)
      double? focalPx;
      if (f35 != null && w != null) {
        focalPx = f35 * (w / 36.0);
      }
      return (focalPx: focalPx, w: w, h: h);
    } catch (_) {
      return (focalPx: null, w: null, h: null);
    }
  }

  int? _exifInt(Map<String, IfdTag> tags, String key) {
    final t = tags[key];
    if (t == null) return null;
    final s = t.printable;
    return int.tryParse(s);
  }

  double? _exifNum(Map<String, IfdTag> tags, String key) {
    final t = tags[key];
    if (t == null) return null;
    final s = t.printable.split('/');
    if (s.length == 2) {
      final a = double.tryParse(s[0]);
      final b = double.tryParse(s[1]);
      if (a != null && b != null && b != 0) return a / b;
    }
    return double.tryParse(t.printable);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_photos.isEmpty) {
      _toast('至少要 1 張主照');
      return;
    }
    setState(() => _submitting = true);

    try {
      final exif = await _extractFocal(_photos.first);
      final List<String> photosB64 = [];
      for (final p in _photos) {
        photosB64.add(await _toBase64(p));
      }
      final String? evidenceB64 =
          _evidence != null ? await _toBase64(_evidence!) : null;

      final body = <String, dynamic>{
        'tree_id': _treeIdCtrl.text.trim(),
        'circumference_cm': double.parse(_circCtrl.text.trim()),
        'capture_distance_m': double.parse(_distCtrl.text.trim()),
        'species': _speciesCtrl.text.trim().isEmpty
            ? null
            : _speciesCtrl.text.trim(),
        'phone_model': _phoneModel,
        'focal_length_px': exif.focalPx,
        'image_width_px': exif.w,
        'image_height_px': exif.h,
        'gps_lat': _gpsLat,
        'gps_lng': _gpsLng,
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'photos': photosB64,
        'evidence_photo': evidenceB64,
      };

      final resp = await ApiService.post('admin/research-dataset', body);
      if (resp['success'] == true) {
        final dbh = (resp['data']?['true_dbh_cm'] as num?)?.toStringAsFixed(2);
        _toast('上傳成功，估算 DBH = ${dbh ?? "?"} cm');
        _resetForm();
        await _fetchList();
      } else {
        _toast('上傳失敗：${resp['message'] ?? "未知錯誤"}');
      }
    } catch (e) {
      _toast('上傳發生錯誤：$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _resetForm() {
    _treeIdCtrl.clear();
    _circCtrl.clear();
    _distCtrl.clear();
    _speciesCtrl.clear();
    _notesCtrl.clear();
    setState(() {
      _photos.clear();
      _evidence = null;
    });
  }

  // ─────────────── 列表 / 刪除 ───────────────

  Future<void> _fetchList() async {
    setState(() => _loadingList = true);
    try {
      final resp = await ApiService.get('admin/research-dataset');
      if (resp['success'] == true && resp['data'] is List) {
        _entries = (resp['data'] as List)
            .cast<Map<String, dynamic>>()
            .toList(growable: false);
      } else {
        _entries = [];
      }
    } catch (_) {
      _entries = [];
    } finally {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  Future<void> _deleteEntry(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('刪除資料'),
        content: Text('確定要刪除 id=$id 的紀錄嗎？\n（Cloudinary 上的圖暫不會刪）'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('刪除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    final resp = await ApiService.delete('admin/research-dataset/$id');
    if (resp['success'] == true) {
      _toast('已刪除');
      await _fetchList();
    } else {
      _toast('刪除失敗：${resp['message'] ?? ""}');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ─────────────── UI ───────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('研究資料蒐集（DBH 校準）'),
        actions: [
          IconButton(
            tooltip: '重新整理列表',
            icon: const Icon(Icons.refresh),
            onPressed: _loadingList ? null : _fetchList,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildIntro(),
              const SizedBox(height: 12),
              _buildForm(),
              const Divider(height: 32),
              _buildList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIntro() {
    return Card(
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('採集流程',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            SizedBox(height: 6),
            Text('1. 用捲尺繞樹幹一圈，量「周長 (cm)」於 1.3m 處（DBH 由系統自動算 = 周長 / π）'),
            Text('2. 站在距樹 0.5–3 m，量「拍攝距離 (m)」'),
            Text('3. 拍 1~3 張主照（同樹輕微角度差），可選拍 1 張「捲尺貼樹」證據照'),
            Text('4. 樹編號自取，例如 NDHU-001、Park-A12'),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _treeIdCtrl,
            decoration: const InputDecoration(
              labelText: '樹編號 *',
              hintText: '如 NDHU-001',
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? '必填' : null,
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _circCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: '周長 (cm) *',
                  border: OutlineInputBorder(),
                ),
                validator: _validatePositive,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _distCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: '拍攝距離 (m) *',
                  border: OutlineInputBorder(),
                ),
                validator: _validatePositive,
              ),
            ),
          ]),
          const SizedBox(height: 10),
          // 預估 DBH 提示（即時）
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _circCtrl,
            builder: (_, v, __) {
              final c = double.tryParse(v.text);
              final dbh = (c != null && c > 0)
                  ? (c / math.pi).toStringAsFixed(2)
                  : '—';
              return Text('  → 預估 DBH ≈ $dbh cm',
                  style: const TextStyle(color: Colors.grey));
            },
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _speciesCtrl,
            decoration: const InputDecoration(
              labelText: '樹種（可空）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _notesCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: '備註（光線/葉幕/地形…可空）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          _buildAutoInfo(),
          const SizedBox(height: 12),
          _buildPhotoRow(),
          const SizedBox(height: 12),
          _buildEvidenceRow(),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload),
            label: Text(_submitting ? '上傳中…' : '送出'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  String? _validatePositive(String? v) {
    if (v == null || v.trim().isEmpty) return '必填';
    final n = double.tryParse(v.trim());
    if (n == null || n <= 0) return '需為正數';
    return null;
  }

  Widget _buildAutoInfo() {
    final gps = (_gpsLat != null && _gpsLng != null)
        ? '${_gpsLat!.toStringAsFixed(6)}, ${_gpsLng!.toStringAsFixed(6)}'
        : '（未取得）';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('手機型號：${_phoneModel ?? "（讀取中…）"}'),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: Text('GPS：$gps')),
            TextButton.icon(
              onPressed: _autoFillGps,
              icon: const Icon(Icons.my_location, size: 18),
              label: const Text('重抓'),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildPhotoRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Text('主照（1~3 張）',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          TextButton.icon(
            onPressed: _photos.length >= 3
                ? null
                : () => _addPhoto(isEvidence: false),
            icon: const Icon(Icons.add_a_photo),
            label: const Text('新增'),
          ),
        ]),
        const SizedBox(height: 6),
        if (_photos.isEmpty)
          const Text('（尚未加入任何照片）',
              style: TextStyle(color: Colors.grey))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(_photos.length, (i) {
              return Stack(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(File(_photos[i].path),
                      width: 100, height: 100, fit: BoxFit.cover),
                ),
                Positioned(
                  right: -6,
                  top: -6,
                  child: IconButton(
                    icon: const Icon(Icons.cancel, color: Colors.red),
                    onPressed: () => _removePhoto(i),
                  ),
                ),
              ]);
            }),
          ),
      ],
    );
  }

  Widget _buildEvidenceRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Text('證據照（捲尺貼樹，可選）',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          TextButton.icon(
            onPressed: () => _addPhoto(isEvidence: true),
            icon: const Icon(Icons.photo_camera),
            label: Text(_evidence == null ? '新增' : '更換'),
          ),
        ]),
        const SizedBox(height: 6),
        if (_evidence != null)
          Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(File(_evidence!.path),
                  width: 100, height: 100, fit: BoxFit.cover),
            ),
            Positioned(
              right: -6,
              top: -6,
              child: IconButton(
                icon: const Icon(Icons.cancel, color: Colors.red),
                onPressed: _removeEvidence,
              ),
            ),
          ])
        else
          const Text('（尚未加入證據照）',
              style: TextStyle(color: Colors.grey)),
      ],
    );
  }

  Widget _buildList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text('歷史紀錄（${_entries.length}）',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16)),
          const Spacer(),
        ]),
        const SizedBox(height: 8),
        if (_loadingList)
          const Center(child: CircularProgressIndicator())
        else if (_entries.isEmpty)
          const Text('（尚無資料）', style: TextStyle(color: Colors.grey))
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _entries.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final r = _entries[i];
              final dbh = (r['true_dbh_cm'] as num?)?.toStringAsFixed(2) ?? '?';
              final dist =
                  (r['capture_distance_m'] as num?)?.toStringAsFixed(2) ?? '?';
              final urls = (r['photo_urls'] as List?)?.cast<String>() ?? [];
              return ListTile(
                leading: urls.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.network(urls.first,
                            width: 56, height: 56, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.broken_image)),
                      )
                    : const Icon(Icons.image_not_supported),
                title: Text(
                    '${r['tree_id']}  DBH=${dbh}cm  d=${dist}m'),
                subtitle: Text([
                  if (r['species'] != null) r['species'],
                  if (r['phone_model'] != null) r['phone_model'],
                  if (r['created_at'] != null)
                    (r['created_at'] as String).split('T').first,
                ].join(' · ')),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _deleteEntry(r['id'] as int),
                ),
              );
            },
          ),
      ],
    );
  }
}
