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
  Map<String, List<Map<String, dynamic>>> _areaCoordinatesMap = {};

  @override
  void initState() {
    super.initState();
    _cleanupAndFetchAreas();
    _fetchAreaCoordinates();
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

  // 獲取區位的坐標資料
  Future<void> _fetchAreaCoordinates() async {
    try {
      final response = await ApiService.get('tree_survey');

      if (response['success'] == true && response['data'] != null) {
        final data = response['data'];
        Map<String, List<Map<String, dynamic>>> areaCoordinates = {};

        // 處理每個樹木資料，根據區位分組並儲存坐標
        for (var tree in data) {
          if (tree['專案區位'] != null &&
              tree['X坐標'] != null &&
              tree['Y坐標'] != null) {
            final area = tree['專案區位'].toString();
            final x = double.tryParse(tree['X坐標'].toString()) ?? 0.0;
            final y = double.tryParse(tree['Y坐標'].toString()) ?? 0.0;

            if (x != 0.0 && y != 0.0) {
              if (!areaCoordinates.containsKey(area)) {
                areaCoordinates[area] = [];
              }

              areaCoordinates[area]!.add({
                'x': x,
                'y': y,
              });
            }
          }
        }

        if (mounted) {
          setState(() {
            _areaCoordinatesMap = areaCoordinates;
          });
        }
      }
    } catch (e) {
      print('獲取區位坐標時發生錯誤: $e');
    }
  }

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

  // 使用坐標判斷區位是否在指定縣市內
  // ignore: unused_element
  bool _isAreaInCity(String area, String city) {
    // 如果沒有坐標資料，則無法判斷
    if (!_areaCoordinatesMap.containsKey(area) ||
        _areaCoordinatesMap[area]!.isEmpty) {
      return false;
    }

    // 定義各縣市的大致坐標範圍
    Map<String, Map<String, double>> cityBounds = {
      '台北': {
        'minLat': 25.01,
        'maxLat': 25.22,
        'minLng': 121.45,
        'maxLng': 121.65
      },
      '新北': {
        'minLat': 24.70,
        'maxLat': 25.30,
        'minLng': 121.28,
        'maxLng': 122.05
      },
      '桃園': {
        'minLat': 24.80,
        'maxLat': 25.10,
        'minLng': 121.10,
        'maxLng': 121.45
      },
      '台中': {
        'minLat': 24.05,
        'maxLat': 24.40,
        'minLng': 120.55,
        'maxLng': 121.05
      },
      '台南': {
        'minLat': 22.90,
        'maxLat': 23.40,
        'minLng': 120.10,
        'maxLng': 120.50
      },
      '高雄': {
        'minLat': 22.40,
        'maxLat': 23.00,
        'minLng': 120.15,
        'maxLng': 120.50
      },
      '基隆': {
        'minLat': 25.05,
        'maxLat': 25.20,
        'minLng': 121.65,
        'maxLng': 121.85
      },
      '新竹': {
        'minLat': 24.70,
        'maxLat': 24.85,
        'minLng': 120.90,
        'maxLng': 121.05
      },
      '嘉義': {
        'minLat': 23.45,
        'maxLat': 23.55,
        'minLng': 120.40,
        'maxLng': 120.50
      },
      '宜蘭': {
        'minLat': 24.50,
        'maxLat': 24.90,
        'minLng': 121.65,
        'maxLng': 121.95
      },
      '花蓮': {
        'minLat': 23.30,
        'maxLat': 24.40,
        'minLng': 121.30,
        'maxLng': 121.65
      },
      '台東': {
        'minLat': 22.50,
        'maxLat': 23.40,
        'minLng': 120.90,
        'maxLng': 121.20
      },
      '澎湖': {
        'minLat': 23.45,
        'maxLat': 23.70,
        'minLng': 119.40,
        'maxLng': 119.70
      },
      '金門': {
        'minLat': 24.40,
        'maxLat': 24.55,
        'minLng': 118.25,
        'maxLng': 118.45
      },
      '連江': {
        'minLat': 25.95,
        'maxLat': 26.30,
        'minLng': 119.90,
        'maxLng': 120.20
      },
      '苗栗': {
        'minLat': 24.25,
        'maxLat': 24.70,
        'minLng': 120.65,
        'maxLng': 121.10
      },
      '彰化': {
        'minLat': 23.85,
        'maxLat': 24.15,
        'minLng': 120.35,
        'maxLng': 120.60
      },
      '南投': {
        'minLat': 23.60,
        'maxLat': 24.10,
        'minLng': 120.75,
        'maxLng': 121.15
      },
      '雲林': {
        'minLat': 23.55,
        'maxLat': 23.80,
        'minLng': 120.15,
        'maxLng': 120.50
      },
      '屏東': {
        'minLat': 22.10,
        'maxLat': 22.80,
        'minLng': 120.40,
        'maxLng': 120.80
      },
    };

    // 檢查該城市是否有定義坐標範圍
    if (!cityBounds.containsKey(city)) {
      return false;
    }

    // 取得城市坐標範圍
    var bounds = cityBounds[city]!;

    // 檢查是否有至少一個坐標點在該城市範圍內
    for (var coord in _areaCoordinatesMap[area]!) {
      double x = coord['x'];
      double y = coord['y'];

      // 檢查坐標點是否在城市範圍內
      if (y >= bounds['minLat']! &&
          y <= bounds['maxLat']! &&
          x >= bounds['minLng']! &&
          x <= bounds['maxLng']!) {
        return true;
      }
    }

    return false;
  }

  // 檢查城市名稱是否與區位匹配
  // ignore: unused_element
  bool _matchCityWithArea(String city, String area) {
    final Map<String, List<String>> cityKeywords = {
      '台北': [
        '台北',
        '臺北',
        '北市',
        '信義',
        '大安',
        '士林',
        '中正',
        '萬華',
        '文山',
        '松山',
        '內湖',
        '南港',
        '北投'
      ],
      '新北': [
        '新北',
        '新北市',
        '板橋',
        '三重',
        '中和',
        '永和',
        '新店',
        '新莊',
        '泰山',
        '林口',
        '淡水',
        '三峽',
        '鶯歌',
        '樹林'
      ],
      '桃園': ['桃園', '桃園市', '中壢', '平鎮', '八德', '楊梅', '龜山', '蘆竹', '大園', '觀音', '龍潭'],
      '台中': [
        '台中',
        '臺中',
        '中市',
        '西屯',
        '南屯',
        '北屯',
        '豐原',
        '大里',
        '太平',
        '沙鹿',
        '梧棲',
        '清水'
      ],
      '台南': ['台南', '臺南', '南市', '安平', '永康', '仁德', '佳里', '新營', '善化', '新化', '麻豆'],
      '高雄': [
        '高雄',
        '高市',
        '鳳山',
        '左營',
        '三民',
        '前鎮',
        '苓雅',
        '大寮',
        '岡山',
        '路竹',
        '橋頭',
        '旗山'
      ],
      '基隆': ['基隆', '基隆市', '七堵', '安樂', '信義', '中山', '仁愛', '暖暖'],
      '新竹': ['新竹', '新竹市', '竹市', '北區', '東區', '香山', '竹北'],
      '嘉義': ['嘉義', '嘉義市', '嘉市', '東區', '西區'],
      '宜蘭': ['宜蘭', '宜蘭縣', '羅東', '礁溪', '頭城', '蘇澳', '五結'],
      '花蓮': ['花蓮', '花蓮縣', '吉安', '新城', '壽豐', '鳳林', '光復'],
      '台東': ['台東', '臺東', '東縣', '關山', '池上', '成功', '卑南', '太麻里'],
      '澎湖': ['澎湖', '澎湖縣', '馬公', '湖西', '白沙', '西嶼'],
      '金門': ['金門', '金門縣', '金沙', '金湖', '金城', '烈嶼'],
      '連江': ['連江', '馬祖', '連江縣', '南竿', '北竿', '東引'],
      '苗栗': ['苗栗', '苗栗縣', '竹南', '頭份', '苑裡', '通霄', '後龍'],
      '彰化': ['彰化', '彰化縣', '員林', '鹿港', '和美', '溪湖', '北斗'],
      '南投': ['南投', '南投縣', '埔里', '草屯', '竹山', '集集', '水里'],
      '雲林': ['雲林', '雲林縣', '斗六', '斗南', '虎尾', '西螺', '北港'],
      '屏東': ['屏東', '屏東縣', '潮州', '東港', '恆春', '萬丹', '長治', '麟洛'],
      '新竹縣': ['新竹縣', '竹縣', '竹東', '湖口', '新豐', '芎林', '寶山'],
      '嘉義縣': ['嘉義縣', '嘉縣', '民雄', '朴子', '大林', '溪口', '太保'],
    };

    final keywords = cityKeywords[city] ?? [city];
    return keywords.any((keyword) => area.contains(keyword));
  }

  Future<void> _fetchProjectsByArea(String area) async {
    try {
      final response =
          await ApiService.get('projects/by_area/${Uri.encodeComponent(area)}');

      if (response['success'] == true) {
        final data = response;

        if (data['data'] != null && data['data'] is List) {
          final List<dynamic> projects = data['data'];

          if (projects.isNotEmpty) {
            // 如果該區位下有專案，跳轉到顯示該區位下專案的頁面
            if (mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => _ProjectsByAreaPage(
                    areaName: area,
                    projects: List<Map<String, dynamic>>.from(
                        projects.map((project) => {
                              'name': project['name'],
                              'code': project['code'],
                              'area': project['area'],
                            })),
                  ),
                ),
              );
            }
            return;
          }
        }
      }

      // 如果沒有專案或API調用失敗，直接進入樹木列表頁面
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TreeSurveyPage(areaName: area),
          ),
        );
      }
    } catch (e) {
      // 發生錯誤時也直接進入樹木列表頁面
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TreeSurveyPage(areaName: area),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    String title = widget.cityName != null ? '${widget.cityName}區位' : '全台專案區位';

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
                                ? '${widget.cityName}沒有專案區位'
                                : '目前沒有專案區位',
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
        title: Text('$areaName專案'),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: projects.length,
        itemBuilder: (context, index) {
          final project = projects[index];
          final projectColor = Colors.teal;
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
                  child: Icon(
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
          gradient: LinearGradient(
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
