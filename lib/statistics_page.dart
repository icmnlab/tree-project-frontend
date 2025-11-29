import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'services/carbon_calculation_service.dart';
import 'services/api_service.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  bool _isLoading = false;
  Map<String, dynamic>? _statistics;
  List<Map<String, dynamic>> _treeData = [];
  double _totalCarbonStorage = 0;
  double _totalAnnualSequestration = 0;

  // 初始化 ApiService 實例
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _fetchStatistics();
    _fetchTreeData();
  }

  Future<void> _fetchStatistics() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 使用 ApiService 來發送請求，確保使用正確的 URL
      final response = await ApiService.get('tree_statistics');

      if (response['success'] == true && response['data'] != null) {
        setState(() {
          _statistics = response['data'];
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('無法載入統計資料')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('發生錯誤: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchTreeData() async {
    try {
      // 使用初始化的 _apiService 實例
      final response = await _apiService.fetchTreeSurveyData();
      setState(() {
        _treeData = response;
        _calculateCarbonMetrics();
      });
    } catch (e) {
      print('Error fetching tree data: $e');
    }
  }

  void _calculateCarbonMetrics() {
    double totalStorage = 0;
    double totalAnnual = 0;

    for (var tree in _treeData) {
      final species = tree['樹種名稱'] ?? '其他';
      final height = double.tryParse(tree['樹高（公尺）'].toString()) ?? 5.0;
      final dbh = double.tryParse(tree['胸徑（公分）'].toString()) ?? 15.0;

      // 估算樹齡（若沒有直接資料）
      int estimatedAge = 10; // 預設值
      if (dbh > 30) {
        estimatedAge = 40;
      } else if (dbh > 20)
        estimatedAge = 25;
      else if (dbh > 10) estimatedAge = 15;

      // 使用新的計算服務
      final carbonStorage =
          CarbonCalculationService.calculateCarbonStorage(species, height, dbh);
      final annualSequestration =
          CarbonCalculationService.calculateAnnualCarbonSequestration(
              species, height, dbh, estimatedAge);

      totalStorage += carbonStorage;
      totalAnnual += annualSequestration;
    }

    setState(() {
      _totalCarbonStorage = totalStorage;
      _totalAnnualSequestration = totalAnnual;
    });
  }

  Widget _buildSpeciesChart() {
    if (_statistics == null || _statistics!['species'] == null) {
      return const Center(child: Text('無資料'));
    }

    final speciesData = _statistics!['species'] as List;
    final topSpecies = speciesData.take(10).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '前十大樹種數量',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          '不選擇樹種則分析該區位全部樹種',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: MediaQuery.of(context).size.width * 0.9,
          height: 300,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: (topSpecies
                            .map(
                                (e) => int.tryParse(e['count'].toString()) ?? 0)
                            .reduce((a, b) => a > b ? a : b) +
                        1) // +1 to have some space on top
                    .toDouble(),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        if (value >= 0 && value < topSpecies.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              topSpecies[value.toInt()]['樹種名稱'],
                              style: const TextStyle(fontSize: 12),
                            ),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(
                  topSpecies.length,
                  (index) => BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: (int.tryParse(
                                    topSpecies[index]['count'].toString()) ??
                                0)
                            .toDouble(),
                        color: Colors.blue.shade700,
                        width: 20,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProjectChart() {
    if (_statistics == null || _statistics!['projects'] == null) {
      return const Center(child: Text('無資料'));
    }

    final projectData = _statistics!['projects'] as List;
    final topProjects = projectData.take(10).toList();

    return Column(
      children: [
        const Text(
          '前十大專案樹木數量',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 300,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: (topProjects
                          .map((e) => int.tryParse(e['count'].toString()) ?? 0)
                          .reduce((a, b) => a > b ? a : b) +
                      1)
                  .toDouble(),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      if (value >= 0 && value < topProjects.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            topProjects[value.toInt()]['專案名稱'],
                            style: const TextStyle(fontSize: 10),
                          ),
                        );
                      }
                      return const Text('');
                    },
                  ),
                ),
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                  ),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              borderData: FlBorderData(show: false),
              barGroups: List.generate(
                topProjects.length,
                (index) => BarChartGroupData(
                  x: index,
                  barRods: [
                    BarChartRodData(
                      toY: (int.tryParse(
                                  topProjects[index]['count'].toString()) ??
                              0)
                          .toDouble(),
                      color: Colors.blue,
                      width: 20,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAreaChart() {
    if (_statistics == null || _statistics!['areas'] == null) {
      return const Center(child: Text('無資料'));
    }

    final areaData = _statistics!['areas'] as List;
    final topAreas = areaData.take(10).toList();

    return Column(
      children: [
        const Text(
          '前十大區位樹木數量',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 300,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: (topAreas
                          .map((e) => int.tryParse(e['count'].toString()) ?? 0)
                          .reduce((a, b) => a > b ? a : b) +
                      1)
                  .toDouble(),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      if (value >= 0 && value < topAreas.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            topAreas[value.toInt()]['專案區位'],
                            style: const TextStyle(fontSize: 10),
                          ),
                        );
                      }
                      return const Text('');
                    },
                  ),
                ),
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                  ),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              borderData: FlBorderData(show: false),
              barGroups: List.generate(
                topAreas.length,
                (index) => BarChartGroupData(
                  x: index,
                  barRods: [
                    BarChartRodData(
                      toY: (int.tryParse(topAreas[index]['count'].toString()) ??
                              0)
                          .toDouble(),
                      color: Colors.orange,
                      width: 20,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSizeStats() {
    if (_statistics == null || _statistics!['sizes'] == null) {
      return const Center(child: Text('無資料'));
    }

    final sizes = _statistics!['sizes'];

    // Helper to safely parse and format numbers
    String formatStat(dynamic value) {
      if (value == null) return 'N/A';
      final double? parsedValue = double.tryParse(value.toString());
      return parsedValue?.toStringAsFixed(2) ?? 'N/A';
    }

    return Card(
      elevation: 4,
      shadowColor: Colors.purple.withOpacity(0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, Colors.purple.shade50],
          ),
        ),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.straighten, color: Colors.purple, size: 22),
                ),
                const SizedBox(width: 12),
                const Text(
                  '樹木尺寸統計',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.purple),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildStatRow('平均樹高', '${formatStat(sizes['avg_height'])} 公尺'),
            _buildStatRow('最大樹高', '${formatStat(sizes['max_height'])} 公尺'),
            _buildStatRow('最小樹高', '${formatStat(sizes['min_height'])} 公尺'),
            const Divider(),
            _buildStatRow('平均胸徑', '${formatStat(sizes['avg_dbh'])} 公分'),
            _buildStatRow('最大胸徑', '${formatStat(sizes['max_dbh'])} 公分'),
            _buildStatRow('最小胸徑', '${formatStat(sizes['min_dbh'])} 公分'),
          ],
        ),
      ),
    );
  }

  Widget _buildCarbonStats() {
    if (_statistics == null || _statistics!['carbon'] == null) {
      return const Center(child: Text('無資料'));
    }

    final carbon = _statistics!['carbon'];

    // Helper to safely parse and format numbers
    String formatStat(dynamic value) {
      if (value == null) return 'N/A';
      final double? parsedValue = double.tryParse(value.toString());
      return parsedValue?.toStringAsFixed(2) ?? 'N/A';
    }

    return Card(
      elevation: 4,
      shadowColor: Colors.green.withOpacity(0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, Colors.green.shade50],
          ),
        ),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.eco, color: Colors.green, size: 22),
                ),
                const SizedBox(width: 12),
                const Text(
                  '碳儲存量統計',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildStatRow('總碳儲存量', '${formatStat(carbon['total_carbon'])} 公斤'),
            _buildStatRow('平均碳儲存量', '${formatStat(carbon['avg_carbon'])} 公斤'),
            const Divider(),
            _buildStatRow('總年碳吸存量', '${formatStat(carbon['total_annual_carbon'])} 公斤'),
            _buildStatRow('平均年碳吸存量', '${formatStat(carbon['avg_annual_carbon'])} 公斤'),
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
          Text(label),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildCarbonOffsetCalculator() {
    return Card(
      elevation: 6,
      shadowColor: Colors.teal.withOpacity(0.3),
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.teal.shade400, Colors.teal.shade700],
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.calculate, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 12),
                const Text('碳足跡抵換計算器',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.trending_up, color: Colors.white70, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '您的樹木每年可吸收約',
                        style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_totalAnnualSequestration.toStringAsFixed(2)} 公斤 CO₂',
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.inventory_2, color: Colors.white70, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '總共儲存了',
                        style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_totalCarbonStorage.toStringAsFixed(2)} 公斤 CO₂',
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
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
        title: const Text('統計分析'),
        backgroundColor: Colors.blue.shade50,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.blue.shade50, Colors.white],
                ),
              ),
              child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSpeciesChart(),
                  const SizedBox(height: 32),
                  _buildProjectChart(),
                  const SizedBox(height: 32),
                  _buildAreaChart(),
                  const SizedBox(height: 32),
                  _buildSizeStats(),
                  const SizedBox(height: 16),
                  _buildCarbonStats(),
                  const SizedBox(height: 32),
                  _buildCarbonOffsetCalculator(),
                ],
              ),
            ),
            ),
    );
  }
}
