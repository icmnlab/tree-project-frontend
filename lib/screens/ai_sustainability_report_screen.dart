import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/api_service.dart';
import '../services/download_service.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../constants/colors.dart';

class AISustainabilityReportScreen extends StatefulWidget {
  const AISustainabilityReportScreen({Key? key}) : super(key: key);

  @override
  _AISustainabilityReportScreenState createState() =>
      _AISustainabilityReportScreenState();
}

class _AISustainabilityReportScreenState
    extends State<AISustainabilityReportScreen> {
  bool _isLoading = false;
  Map<String, dynamic>? _reportData;
  String? _error;

  // 區域和樹種資料
  List<String> _projectAreas = [];
  List<String> _species = [];

  // 已選擇的過濾條件
  final List<String> _selectedProjectAreas = [];
  List<String> _selectedSpecies = [];
  RangeValues _dbhRange = const RangeValues(0, 100);
  double _maxDbhValue = 100;

  // 加載狀態
  bool _isLoadingAreas = false;
  bool _isLoadingSpecies = false;

  @override
  void initState() {
    super.initState();
    _loadProjectAreas();
    _loadMaxDbh(); // 加載最大胸徑值
  }

  // 載入專案區位
  Future<void> _loadProjectAreas() async {
    setState(() {
      _isLoadingAreas = true;
    });

    try {
      final response = await ApiService.get('tree_statistics');
      if (response['success'] == true && response['data']['areas'] != null) {
        final areas = response['data']['areas'] as List;
        setState(() {
          _projectAreas = areas.map((area) => area['專案區位'].toString()).toList();
          _isLoadingAreas = false;
        });
      } else {
        setState(() {
          _error = '無法加載專案區位';
          _isLoadingAreas = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = '加載專案區位時發生錯誤: $e';
        _isLoadingAreas = false;
      });
    }
  }

  // 根據所選區域載入樹種
  Future<void> _loadSpeciesByArea() async {
    if (_selectedProjectAreas.isEmpty) {
      setState(() {
        _species = [];
        _selectedSpecies = [];
      });
      return;
    }

    setState(() {
      _isLoadingSpecies = true;
    });

    try {
      // 構建按多個區域過濾的 API 請求
      final areas = _selectedProjectAreas
          .map((area) => Uri.encodeComponent(area))
          .join(',');
      final response = await ApiService.get('tree_statistics?areas=$areas');
      if (response['success'] == true && response['data']['species'] != null) {
        final speciesData = response['data']['species'] as List;
        setState(() {
          _species = speciesData.map((s) => s['樹種名稱'].toString()).toList();
          _selectedSpecies = [];
          _isLoadingSpecies = false;
        });
      } else {
        setState(() {
          _species = [];
          _selectedSpecies = [];
          _isLoadingSpecies = false;
        });
      }
    } catch (e) {
      setState(() {
        _species = [];
        _selectedSpecies = [];
        _isLoadingSpecies = false;
        _error = '加載樹種時發生錯誤: $e';
      });
    }
  }

  // 載入最大胸徑值
  Future<void> _loadMaxDbh() async {
    try {
      final response = await ApiService.get('tree_statistics');
      if (response['success'] == true && response['data']['sizes'] != null) {
        final sizes = response['data']['sizes'];
        if (sizes['max_dbh'] != null) {
          setState(() {
            _maxDbhValue = double.parse(sizes['max_dbh'].toString());
            _dbhRange = RangeValues(0, _maxDbhValue);
          });
        }
      }
    } catch (e) {
      // 如果加載失敗，保持默認值
      print('加載最大胸徑值時發生錯誤: $e');
    }
  }

  Future<void> _fetchReportData() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _reportData = null;
    });

    try {
      // 構建查詢參數
      final Map<String, String> queryParams = {};

      if (_selectedProjectAreas.isNotEmpty) {
        queryParams['projectAreas'] = _selectedProjectAreas.join(',');
      }

      if (_selectedSpecies.isNotEmpty) {
        queryParams['species'] = _selectedSpecies.join(',');
      }

      if (_dbhRange.start > 0) {
        queryParams['minDbh'] = _dbhRange.start.toStringAsFixed(1);
      }

      if (_dbhRange.end < _maxDbhValue) {
        queryParams['maxDbh'] = _dbhRange.end.toStringAsFixed(1);
      }

      // 構建查詢字符串
      String queryString = '';
      if (queryParams.isNotEmpty) {
        queryString =
            '?${queryParams.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}';
      }

      final response =
          await ApiService.get('reports/ai-sustainability$queryString');

      if (!mounted) return;

      if (response['success'] == true && response['data'] != null) {
        setState(() {
          _reportData = response['data'];
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = response['message'] ?? '無法載入報告數據';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = '連接伺服器時發生錯誤: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _downloadPdfReport() async {
    final Map<String, String> queryParams = {};
    if (_selectedProjectAreas.isNotEmpty) {
      queryParams['projectAreas'] = _selectedProjectAreas.join(',');
    }
    if (_selectedSpecies.isNotEmpty) {
      queryParams['species'] = _selectedSpecies.join(',');
    }
    if (_dbhRange.start > 0) {
      queryParams['minDbh'] = _dbhRange.start.toStringAsFixed(1);
    }
    if (_dbhRange.end < _maxDbhValue) {
      queryParams['maxDbh'] = _dbhRange.end.toStringAsFixed(1);
    }

    String queryString = '';
    if (queryParams.isNotEmpty) {
      queryString =
          '?${queryParams.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}';
    }

    final String pdfUrl =
        '${ApiService.baseUrl}/reports/ai-sustainability/pdf$queryString';

    final result = await DownloadService.downloadAndOpen(
      pdfUrl,
      suggestedFilename: 'ai_sustainability_report.pdf',
    );

    if (mounted) {
      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.warning ?? 'PDF 報告已下載並開啟')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.error ?? '下載失敗')),
        );
      }
    }
  }

  Widget _buildFilterForm() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('設置報告過濾條件', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),

            // 專案區位多選
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('專案區位選擇'),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: _isLoadingAreas
                      ? const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : _projectAreas.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Center(child: Text('無可用專案區位')),
                            )
                          : Wrap(
                              children: _projectAreas.map((area) {
                                return Padding(
                                  padding: const EdgeInsets.all(4.0),
                                  child: FilterChip(
                                    label: Text(area),
                                    selected:
                                        _selectedProjectAreas.contains(area),
                                    onSelected: (selected) {
                                      setState(() {
                                        if (selected) {
                                          _selectedProjectAreas.add(area);
                                        } else {
                                          _selectedProjectAreas.remove(area);
                                        }
                                      });
                                      _loadSpeciesByArea();
                                    },
                                  ),
                                );
                              }).toList(),
                            ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // 樹種多選
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('樹種選擇'),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: _isLoadingSpecies
                      ? const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : _species.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Center(child: Text('請先選擇專案區位')),
                            )
                          : Wrap(
                              children: _species.map((species) {
                                return Padding(
                                  padding: const EdgeInsets.all(4.0),
                                  child: FilterChip(
                                    label: Text(species),
                                    selected:
                                        _selectedSpecies.contains(species),
                                    onSelected: (selected) {
                                      setState(() {
                                        if (selected) {
                                          _selectedSpecies.add(species);
                                        } else {
                                          _selectedSpecies.remove(species);
                                        }
                                      });
                                    },
                                  ),
                                );
                              }).toList(),
                            ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // 胸徑範圍滑桿
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '胸徑範圍: ${_dbhRange.start.toInt()} - ${_dbhRange.end.toInt()} 公分'),
                RangeSlider(
                  values: _dbhRange,
                  min: 0,
                  max: _maxDbhValue,
                  divisions: _maxDbhValue.toInt(),
                  labels: RangeLabels(
                    _dbhRange.start.round().toString(),
                    _dbhRange.end.round().toString(),
                  ),
                  onChanged: (RangeValues values) {
                    setState(() {
                      _dbhRange = values;
                    });
                  },
                ),
              ],
            ),

            const SizedBox(height: 16),

            // 已選過濾條件顯示
            if (_selectedProjectAreas.isNotEmpty ||
                _selectedSpecies.isNotEmpty ||
                _dbhRange.start > 0 ||
                _dbhRange.end < _maxDbhValue)
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('已選擇的過濾條件:'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ..._selectedProjectAreas.map((area) => Chip(
                              label: Text('區位: $area'),
                              onDeleted: () {
                                setState(() {
                                  _selectedProjectAreas.remove(area);
                                  if (_selectedProjectAreas.isEmpty) {
                                    _selectedSpecies = [];
                                    _species = [];
                                  } else {
                                    _loadSpeciesByArea();
                                  }
                                });
                              },
                            )),
                        ..._selectedSpecies.map((species) => Chip(
                              label: Text('樹種: $species'),
                              onDeleted: () {
                                setState(() {
                                  _selectedSpecies.remove(species);
                                });
                              },
                            )),
                        if (_dbhRange.start > 0 || _dbhRange.end < _maxDbhValue)
                          Chip(
                            label: Text(
                                '胸徑: ${_dbhRange.start.toInt()}-${_dbhRange.end.toInt()} 公分'),
                            onDeleted: () {
                              setState(() {
                                _dbhRange = RangeValues(0, _maxDbhValue);
                              });
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _fetchReportData,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(
                        color: Colors.white,
                      )
                    : const Text('生成 AI 永續報告'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAIAnalysis() {
    if (_reportData == null || !_reportData!.containsKey('aiAnalysis')) {
      return Container();
    }

    final aiAnalysis = _reportData!['aiAnalysis'] as String;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: AppColors.forestGreen),
                const SizedBox(width: 8),
                Text('AI 永續發展分析',
                    style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 16),
            MarkdownBody(
              data: aiAnalysis,
              styleSheet:
                  MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                p: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontSize: 14),
                h1: Theme.of(context).textTheme.headlineSmall,
                h2: Theme.of(context).textTheme.titleLarge,
                h3: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBasicStats() {
    if (_reportData == null || _reportData!['basicStats'] == null)
      return Container();
    final stats = _reportData!['basicStats'];

    // Helper function to safely format numbers, handling nulls
    String formatNumber(dynamic number, [int decimals = 2]) {
      if (number == null) return 'N/A';
      if (number is num) return number.toStringAsFixed(decimals);
      return number.toString(); // Fallback for unexpected types
    }

    // Safely get values for kg
    final totalCarbonKg = formatNumber(stats['total_carbon_storage']);
    final annualCarbonKg =
        formatNumber(stats['total_annual_carbon_sequestration']);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('基本統計數據', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            _buildStatRow('總樹木數量', '${stats['total_trees'] ?? 'N/A'} 棵'),
            _buildStatRow('物種數量', '${stats['species_count'] ?? 'N/A'} 種'),
            _buildStatRow('平均樹高', '${formatNumber(stats['avg_height'])} 公尺'),
            _buildStatRow('平均胸徑', '${formatNumber(stats['avg_dbh'])} 公分'),
            // Only display kg for carbon storage
            _buildStatRow('總碳儲存量', '$totalCarbonKg 公斤'),
            // Only display kg for annual carbon sequestration
            _buildStatRow('年碳吸存量', '$annualCarbonKg 公斤/年'),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyLarge),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildSpeciesDiversityChart() {
    if (_reportData == null || _reportData!['speciesDiversity'] == null) {
      return Container();
    }
    final speciesData = _reportData!['speciesDiversity'] as List;

    // [FIX] Safely parse 'count' which might be a String from the DB
    var topSpecies = List.from(speciesData);
    topSpecies.sort((a, b) {
      final num countB = num.tryParse(b['count'].toString()) ?? 0;
      final num countA = num.tryParse(a['count'].toString()) ?? 0;
      return countB.compareTo(countA);
    });

    List<dynamic> chartData = [];
    double otherCount = 0;
    double totalCount = 0;

    // 計算總數
    for (var species in topSpecies) {
      totalCount += (num.tryParse(species['count'].toString()) ?? 0).toDouble();
    }

    // 取前5項，其餘歸為"其他"
    if (topSpecies.length > 5) {
      for (int i = 0; i < topSpecies.length; i++) {
        if (i < 5) {
          chartData.add(topSpecies[i]);
        } else {
          otherCount +=
              (num.tryParse(topSpecies[i]['count'].toString()) ?? 0).toDouble();
        }
      }

      // 添加"其他"類別
      if (otherCount > 0) {
        chartData.add({
          '樹種名稱': '其他',
          'count': otherCount,
          'percentage': (otherCount / totalCount) * 100
        });
      }
    } else {
      chartData = topSpecies;
    }

    // 定義顏色
    final List<Color> colors = [
      Colors.green,
      Colors.blue,
      Colors.orange,
      Colors.red,
      Colors.purple,
      Colors.grey,
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('物種多樣性分析 (Top 5)',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('顯示出現頻率最高的前5種樹木，其餘歸類為"其他"'),
            const SizedBox(height: 16),
            SizedBox(
              height: 250,
              child: Row(
                children: [
                  // 圓餅圖
                  Expanded(
                    flex: 3,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 40,
                        sections: List.generate(chartData.length, (index) {
                          final data = chartData[index];
                          final count =
                              num.tryParse(data['count'].toString()) ?? 0;
                          // [FIX] Also safely parse 'percentage' which might be a String
                          final percentage =
                              num.tryParse(data['percentage'].toString()) ??
                                  0.0;
                          return PieChartSectionData(
                            value: count.toDouble(),
                            title: '${percentage.toStringAsFixed(1)}%',
                            radius: 100,
                            color: colors[index % colors.length],
                            titleStyle: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.white),
                          );
                        }),
                      ),
                    ),
                  ),
                  // 圖例
                  Expanded(
                    flex: 2,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List.generate(chartData.length, (index) {
                        final data = chartData[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Row(
                            children: [
                              Container(
                                width: 16,
                                height: 16,
                                color: colors[index % colors.length],
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${data['樹種名稱']} (${(num.tryParse(data['count'].toString()) ?? 0).toInt()})',
                                  style: const TextStyle(fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 永續報告'),
        actions: [
          if (_reportData != null && !_isLoading)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              onPressed: _downloadPdfReport,
              tooltip: '匯出 PDF',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFilterForm(),
            const SizedBox(height: 16),
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('生成 AI 報告中，這可能需要幾秒鐘...')
                    ],
                  ),
                ),
              )
            else if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child:
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                ),
              )
            else if (_reportData != null) ...[
              _buildAIAnalysis(),
              const SizedBox(height: 16),
              _buildBasicStats(),
              const SizedBox(height: 16),
              _buildSpeciesDiversityChart(),
              const SizedBox(height: 32),
              Center(
                child: Text(
                  '報告生成時間: ${_reportData?['generatedAt'] != null ? DateTime.parse(_reportData!['generatedAt']).toString() : '未知'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
