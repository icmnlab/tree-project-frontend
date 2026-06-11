import 'package:flutter/material.dart';
import '../services/tree_service.dart';
import '../tree_survey_detail_page.dart';

/// 全域樹木搜尋：以系統/專案編號、樹種、專案名稱等關鍵字查詢，點結果直達詳情。
///
/// 重用後端既有搜尋（`GET /tree_survey?q=`，見 `TreeService.getAllTrees`），
/// 不另開 API、不動既有頁面結構，純加值的瀏覽入口。
class TreeSearchDelegate extends SearchDelegate<void> {
  TreeSearchDelegate() : super(searchFieldLabel: '搜尋樹木（編號 / 樹種 / 區）');

  final TreeService _treeService = TreeService();

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () => query = '',
          ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildSuggestions(BuildContext context) {
    // 建議清單要求 ≥2 字元才查詢，避免逐鍵打 API；按 Enter 走 buildResults。
    if (query.trim().length < 2) {
      return const _SearchHint();
    }
    return _results(context);
  }

  @override
  Widget buildResults(BuildContext context) => _results(context);

  Widget _results(BuildContext context) {
    final q = query.trim();
    if (q.isEmpty) return const _SearchHint();
    return FutureBuilder<Map<String, dynamic>>(
      // key 讓每次查詢字串變更都重建 Future，避免顯示舊結果。
      key: ValueKey(q),
      future: _treeService.getAllTrees(search: q, limit: 50),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('搜尋失敗：${snapshot.error}'));
        }
        final data = snapshot.data;
        final list = (data?['data'] is List)
            ? List<Map<String, dynamic>>.from(data!['data'] as List)
            : <Map<String, dynamic>>[];
        if (list.isEmpty) {
          return Center(child: Text('找不到符合「$q」的樹木'));
        }
        return ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final tree = list[i];
            final species = tree['樹種名稱']?.toString() ?? '未知樹種';
            final project = tree['專案名稱']?.toString() ?? '—';
            final area = tree['專案區位']?.toString() ?? '—';
            final systemId =
                tree['系統樹木']?.toString() ?? tree['id']?.toString() ?? '—';
            final projectTreeId = tree['專案樹木']?.toString();
            final idLabel = (projectTreeId != null && projectTreeId.isNotEmpty)
                ? '$systemId · $projectTreeId'
                : systemId;
            return ListTile(
              leading: const Icon(Icons.park, color: Colors.green),
              title: Text(species),
              subtitle: Text('$project ／ $area\n$idLabel'),
              isThreeLine: true,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TreeSurveyDetailPage(treeData: tree),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _SearchHint extends StatelessWidget {
  const _SearchHint();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text(
              '輸入系統/區編號、樹種或區名稱開始搜尋',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
