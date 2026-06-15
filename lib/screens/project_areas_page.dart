import 'package:flutter/material.dart';
import '../project_trees_page.dart';
import '../tree_survey_page.dart';
import 'cities_page.dart';
import '../services/api_service.dart';
import '../constants/colors.dart';

class ProjectAreasPage extends StatefulWidget {
  final String? cityName;

  const ProjectAreasPage({Key? key, this.cityName}) : super(key: key);

  @override
  State<ProjectAreasPage> createState() => _ProjectAreasPageState();
}

class _ProjectAreasPageState extends State<ProjectAreasPage> {
  List<Map<String, dynamic>> _areas = [];
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _cleanupAndFetchAreas();
  }

  // 先呼叫 cleanup API，再載入區位
  Future<void> _cleanupAndFetchAreas() async {
    try {
      await ApiService.triggerCleanup();
    } catch (e) {
      // 忽略清理失敗，繼續載入
    }
    await _fetchProjectAreas();
  }

  // [Stage 1] _fetchAreaCoordinates / _areaCoordinatesMap 已移除
  // 原本只被死的 _isAreaInCity 使用；現在縣市過濾由伺服器負責。

  Future<void> _fetchProjectAreas() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // 構建 URL，如果有指定城市則加入查詢參數
      String endpoint = 'project_areas';
      if (widget.cityName != null) {
        endpoint = 'project_areas?city=${widget.cityName}';
      }
      final response = await ApiService.get(endpoint);

      if (response['success'] == true) {
        final data = response;

        setState(() {
          if (data['data'] != null) {
            final List<dynamic> areasData = data['data'];
            _areas = List<Map<String, dynamic>>.from(areasData);
          } else {
            _areas = [];
          }
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = '無法載入資料: ${response['message'] ?? '未知錯誤'}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '發生錯誤: $e';
        _isLoading = false;
      });
    }
  }

  // [Stage 1] _isAreaInCity / _matchCityWithArea 已移除
  // 縣市判斷統一在後端 utils/county.resolveAreaCity (內政部官方界線 + 港口權威表)，
  // 區位列表現由 GET /api/project_areas?city=X 直接過濾，前端不再需要 cityBounds/cityKeywords。

  Future<void> _fetchProjectsByArea(String area) async {
    List<Map<String, dynamic>> projects = [];
    try {
      // [Bug A 修復] 帶上 cityName，後端按 project_areas.city 或樹木座標解析縣市過濾
      final cityQuery = widget.cityName != null
          ? '?city=${Uri.encodeComponent(widget.cityName!)}'
          : '';
      final response =
          await ApiService.get('projects/by_area/${Uri.encodeComponent(area)}$cityQuery');

      if (response['success'] == true && response['data'] is List) {
        final List<dynamic> data = response['data'];
        projects = List<Map<String, dynamic>>.from(data.map((p) => {
              'name': p['name'],
              'code': p['code'],
              'area': p['area'],
            }));
      }
    } catch (e) {
      // 即便 API 失敗，仍進入專案列表頁顯示空狀態，由使用者決定下一步
      // (而非自動跳到 TreeSurveyPage 越過區位 → 專案的層級)
    }

    // [P3 / Bug 3c 修復] 永遠進入 _ProjectsByAreaPage：
    //   - 不再因為「空清單 / API fail」就 fallback 到 TreeSurveyPage
    //   - _ProjectsByAreaPage 已支援空狀態 + FAB 可選擇查看所有樹木
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => _ProjectsByAreaPage(
            areaName: area,
            projects: projects,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    String title = widget.cityName != null ? '${widget.cityName}專案' : '全台專案';

    // [B5]
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkCard : Colors.white;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.location_city),
            tooltip: '切換城市',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CitiesPage(),
                ),
              ).then((_) => _cleanupAndFetchAreas());
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cleanupAndFetchAreas,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? Center(child: Text(_errorMessage))
              : _areas.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.location_off,
                            size: 80,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            widget.cityName != null
                                ? '${widget.cityName}沒有專案'
                                : '目前沒有專案',
                            style: const TextStyle(fontSize: 18),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _areas.length,
                      itemBuilder: (context, index) {
                        final area = _areas[index];
                        final areaColor = Colors.primaries[index % Colors.primaries.length];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 6,
                          ),
                          elevation: 4,
                          shadowColor: areaColor.withValues(alpha:0.3),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: LinearGradient(
                                  colors: [cardBg, areaColor.withValues(alpha:0.08)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              leading: Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [areaColor.withValues(alpha:0.7), areaColor],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.location_on,
                                  color: Colors.white,
                                  size: 26,
                                ),
                              ),
                              title: Text(
                                area['area_name'] ?? '',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: areaColor.withValues(alpha:0.9),
                                ),
                              ),
                              subtitle: area['area_code'] != null
                                  ? Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text('代碼: ${area['area_code']}'),
                                    )
                                  : null,
                              trailing: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: areaColor.withValues(alpha:0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.arrow_forward_ios,
                                  size: 16,
                                  color: areaColor,
                                ),
                              ),
                              onTap: () =>
                                  _fetchProjectsByArea(area['area_name'] ?? ''),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}

class _ProjectsByAreaPage extends StatelessWidget {
  final String areaName;
  final List<Map<String, dynamic>> projects;

  const _ProjectsByAreaPage({
    Key? key,
    required this.areaName,
    required this.projects,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // [B5]
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkCard : Colors.white;

    return Scaffold(
      appBar: AppBar(
        title: Text('$areaName區'),
      ),
      body: projects.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.folder_off, size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text('此專案目前沒有可顯示的區',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      '可能因縣市過濾或權限不足。\n按右下角按鈕直接查看所有樹木。',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: projects.length,
        itemBuilder: (context, index) {
          final project = projects[index];
          const projectColor = Colors.teal;
          return Card(
            margin: const EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 6,
            ),
            elevation: 4,
            shadowColor: projectColor.withValues(alpha:0.3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: [cardBg, projectColor.withValues(alpha:0.08)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                leading: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [projectColor.shade400, projectColor.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.folder,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                title: Text(
                  project['name'],
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: projectColor.shade700,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('代碼: ${project['code']}'),
                ),
                trailing: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: projectColor.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: projectColor,
                  ),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ProjectTreesPage(
                        projectName: project['name'],
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.leafGreen, AppColors.forestGreen],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.forestGreen.withValues(alpha:0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FloatingActionButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => TreeSurveyPage(areaName: areaName),
              ),
            );
          },
          backgroundColor: Colors.transparent,
          elevation: 0,
          tooltip: '查看所有樹木',
          child: const Icon(Icons.list, size: 28),
        ),
      ),
    );
  }
}
