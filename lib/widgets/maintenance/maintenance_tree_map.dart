import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../utils/safe_map_camera.dart';
import '../../utils/tree_id_display.dart';

/// 維護量測：區內樹木地圖（點選標記 → 由父層顯示確認）
class MaintenanceTreeMap extends StatefulWidget {
  final List<Map<String, dynamic>> trees;
  final void Function(Map<String, dynamic> tree) onTreeTap;
  final String gpsCoverageHint;
  final String emptyMessage;
  final String tapHint;

  const MaintenanceTreeMap({
    super.key,
    required this.trees,
    required this.onTreeTap,
    required this.gpsCoverageHint,
    required this.emptyMessage,
    required this.tapHint,
  });

  @override
  State<MaintenanceTreeMap> createState() => _MaintenanceTreeMapState();
}

class _MaintenanceTreeMapState extends State<MaintenanceTreeMap> {
  final SafeMapCamera _camera = SafeMapCamera(logTag: 'MaintMap');
  static const _defaultCenter = LatLng(23.7, 121.0);

  LatLng? _parsePosition(Map<String, dynamic> tree) {
    final lat = _asDouble(tree['y_coord'] ?? tree['Y坐標']);
    final lng = _asDouble(tree['x_coord'] ?? tree['X坐標']);
    if (lat == null || lng == null || lat == 0 || lng == 0) return null;
    return LatLng(lat, lng);
  }

  double? _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '');
  }

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};
    for (final tree in widget.trees) {
      final pos = _parsePosition(tree);
      if (pos == null) continue;
      final id = tree['id'] ?? tree['ID'];
      final pt = tree['project_tree_id'] ?? tree['專案樹木'];
      final st = tree['system_tree_id'] ?? tree['系統樹木'];
      final label = TreeIdDisplay.fieldListLabel(
        projectTreeId: pt?.toString(),
        systemTreeId: st?.toString(),
      );
      final species =
          (tree['species_name'] ?? tree['樹種名稱'] ?? '—').toString();
      markers.add(
        Marker(
          markerId: MarkerId('maint_$id'),
          position: pos,
          infoWindow: InfoWindow(title: label, snippet: species),
          onTap: () => widget.onTreeTap(tree),
        ),
      );
    }
    return markers;
  }

  Future<void> _fitBounds(Set<Marker> markers) async {
    await _camera.fitMarkers(markers);
  }

  @override
  void didUpdateWidget(MaintenanceTreeMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trees != widget.trees && _camera.ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitBounds(_buildMarkers());
      });
    }
  }

  @override
  void dispose() {
    _camera.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final markers = _buildMarkers();
    final withGps = markers.length;
    final total = widget.trees.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (total > 0)
          Material(
            color: withGps < total ? Colors.amber.shade50 : Colors.teal.shade50,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                widget.gpsCoverageHint
                    .replaceAll('{shown}', '$withGps')
                    .replaceAll('{total}', '$total'),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        if (withGps > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Text(
              widget.tapHint,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ),
        Expanded(
          child: markers.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      widget.emptyMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ),
                )
              : Stack(
                  children: [
                    GoogleMap(
                      onMapCreated: (c) async {
                        _camera.attach(c);
                        await _camera.markReadyAfterPlatformInit();
                        if (!mounted) return;
                        await _fitBounds(markers);
                      },
                      initialCameraPosition: const CameraPosition(
                        target: _defaultCenter,
                        zoom: 14,
                      ),
                      markers: markers,
                      myLocationButtonEnabled: true,
                      myLocationEnabled: true,
                      zoomControlsEnabled: false,
                      mapToolbarEnabled: false,
                    ),
                    Positioned(
                      right: 12,
                      bottom: 16,
                      child: FloatingActionButton.small(
                        heroTag: 'maint_map_loc',
                        onPressed: () => _fitBounds(markers),
                        tooltip: widget.tapHint,
                        child: const Icon(Icons.fit_screen),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
