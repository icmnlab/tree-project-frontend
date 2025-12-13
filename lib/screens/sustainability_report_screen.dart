import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/api_service.dart';
import 'dart:math' as math;
import '../services/download_service.dart';

class SustainabilityReportScreen extends StatefulWidget {
  const SustainabilityReportScreen({Key? key}) : super(key: key);

  @override
  _SustainabilityReportScreenState createState() =>
      _SustainabilityReportScreenState();
}

class _SustainabilityReportScreenState
    extends State<SustainabilityReportScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _reportData;
  String? _error;
  Map<String, String> _currentFilters = {};

  @override
  void initState() {
    super.initState();
    _fetchReportData({});
  }

  Future<void> _fetchReportData(Map<String, String> filters) async {
    setState(() {
      _isLoading = true;
      _currentFilters = filters;
      _error = null;
      _reportData = null;
    });
    try {
      String endpoint = 'reports/ai-sustainability';
      if (filters.isNotEmpty) {
        final queryParams = Uri(queryParameters: filters).query;
        endpoint += '?$queryParams';
      }

      final response = await ApiService.get(endpoint);

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
    String queryString = Uri(queryParameters: _currentFilters).query;
    final String pdfUrl =
        '${ApiService.baseUrl}/reports/ai-sustainability/pdf?$queryString';

    final result = await DownloadService.downloadAndOpen(
      pdfUrl,
      suggestedFilename: 'sustainability_report.pdf',
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

  Widget _buildBasicStats() {
    if (_reportData == null) return Container();
    final stats = _reportData!['basicStats'];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('基本統計數據', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            _buildStatRow('總樹木數量', '${stats['total_trees']} 棵'),
            _buildStatRow('物種數量', '${stats['species_count']} 種'),
            _buildStatRow(
                '平均樹高', '${stats['avg_height'].toStringAsFixed(2)} 公尺'),
            _buildStatRow('平均胸徑', '${stats['avg_dbh'].toStringAsFixed(2)} 公分'),
            _buildStatRow('總碳儲存量',
                '${stats['total_carbon_storage'].toStringAsFixed(2)} 公斤'),
            _buildStatRow('年碳吸存量',
                '${stats['total_annual_carbon_sequestration'].toStringAsFixed(2)} 公斤/年'),
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
    if (_reportData == null) return Container();
    final speciesData = _reportData!['speciesDiversity'] as List;

    var topSpecies = List.from(speciesData);
    topSpecies.sort((a, b) => (b['count'] as num).compareTo(a['count'] as num));

    List<dynamic> chartData = [];
    double otherCount = 0;
    double totalCount = 0;

    for (var species in topSpecies) {
      totalCount += species['count'].toDouble();
    }

    if (topSpecies.length > 5) {
      for (int i = 0; i < topSpecies.length; i++) {
        if (i < 5) {
          chartData.add(topSpecies[i]);
        } else {
          otherCount += topSpecies[i]['count'].toDouble();
        }
      }

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
                  Expanded(
                    flex: 3,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 40,
                        sections: List.generate(chartData.length, (index) {
                          final data = chartData[index];
                          return PieChartSectionData(
                            value: data['count'].toDouble(),
                            title: '${data['percentage'].toStringAsFixed(1)}%',
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
                                  '${data['樹種名稱']} (${data['count'].toInt()})',
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

  Widget _buildHealthStatusChart() {
    if (_reportData == null) return Container();
    final healthData = _reportData!['healthStatus'] as List;

    final Map<String, Color> healthColors = {
      '良好': Colors.green,
      '一般': Colors.yellow,
      '不佳': Colors.orange,
      '危險': Colors.red,
      '未知': Colors.grey,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('健康狀況分析', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            SizedBox(
              height: 250,
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 40,
                        sections: healthData.map((data) {
                          final status = data['狀況'] ?? '未知';
                          return PieChartSectionData(
                            value: data['count'].toDouble(),
                            title: '${data['percentage'].toStringAsFixed(1)}%',
                            radius: 100,
                            color: healthColors[status] ?? Colors.grey,
                            titleStyle: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: healthData.map((data) {
                        final status = data['狀況'] ?? '未知';
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Row(
                            children: [
                              Container(
                                width: 16,
                                height: 16,
                                color: healthColors[status] ?? Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '$status (${data['count'].toInt()} 棵)',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
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

  Widget _buildDbhDistributionChart() {
    if (_reportData == null) return Container();
    final dbhData = _reportData!['dbhDistribution'] as List;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('徑級分佈', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            SizedBox(
              height: 250,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: dbhData.fold(
                          0.0,
                          (max, item) => math.max(
                              max, (item['percentage'] as num).toDouble())) *
                      1.1,
                  titlesData: FlTitlesData(
                    show: true,
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= dbhData.length) {
                            return const SizedBox();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 10.0),
                            child: Text(
                              dbhData[index]['dbh_range'],
                              style: const TextStyle(fontSize: 10),
                              textAlign: TextAlign.center,
                            ),
                          );
                        },
                        reservedSize: 30,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '${value.toInt()}%',
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                        reservedSize: 40,
                      ),
                    ),
                  ),
                  gridData: const FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 10,
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(dbhData.length, (index) {
                    final data = dbhData[index];
                    // ignore: unused_local_variable
                    final count = data['count'] as int; // Reserved for tooltip display
                    final percentage = data['percentage'] as num;

                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: percentage.toDouble(),
                          color: Colors.green.withOpacity(0.7),
                          width: 20,
                          borderRadius: BorderRadius.circular(2),
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: 100,
                            color: Colors.grey.withOpacity(0.1),
                          ),
                        ),
                      ],
                      showingTooltipIndicators: [0],
                    );
                  }),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final data = dbhData[group.x.toInt()];
                        return BarTooltipItem(
                          '${data['dbh_range']}\n${data['count']} 棵 (${data['percentage'].toStringAsFixed(1)}%)',
                          const TextStyle(color: Colors.white),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('AI 永續報告')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('AI 永續報告')),
        body: Center(
            child: Padding(
          padding: const EdgeInsets.all(16.0),
          child:
              Text('載入錯誤: $_error\n請檢查網路連線或稍後再試。', textAlign: TextAlign.center),
        )),
      );
    }

    if (_reportData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('AI 永續報告')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('沒有可顯示的報告數據。'),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () => _fetchReportData({}),
                child: const Text('重新載入'),
              )
            ],
          ),
        ),
      );
    }

    final String aiAnalysisText =
        _reportData!['aiAnalysis'] as String? ?? 'AI 分析內容未提供。';

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
            Card(
              elevation: 2,
              margin: const EdgeInsets.symmetric(vertical: 8.0),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AI 分析與洞察',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(color: Theme.of(context).primaryColor)),
                    const SizedBox(height: 12),
                    SelectableText(
                      aiAnalysisText,
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.justify,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('數據摘要',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const Divider(height: 20, thickness: 1),
            _buildBasicStats(),
            const SizedBox(height: 16),
            _buildSpeciesDiversityChart(),
            const SizedBox(height: 16),
            _buildHealthStatusChart(),
            const SizedBox(height: 16),
            _buildDbhDistributionChart(),
            const SizedBox(height: 32),
            Center(
              child: Text(
                '報告生成時間: ${_reportData!['generatedAt'] != null ? DateTime.parse(_reportData!['generatedAt']).toLocal().toString().substring(0, 19) : '未知'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
