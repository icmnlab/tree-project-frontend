import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:fl_chart/fl_chart.dart';
import 'services/carbon_calculation_service.dart';
import 'services/api_service.dart';
import 'constants/colors.dart';
import 'services/locale_service.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  Map<String, dynamic>? _statistics;
  List<Map<String, dynamic>> _treeData = [];
  double _totalCarbonStorage = 0;
  double _totalAnnualSequestration = 0;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // 初始化 ApiService 實例
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _fetchStatistics();
    _fetchTreeData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _fetchStatistics() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await ApiService.get('tree_statistics');

      if (response['success'] == true && response['data'] != null) {
        if (!mounted) return;
        setState(() {
          _statistics = response['data'];
        });
        _animationController.forward();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(LocaleService.instance.t('stats_load_failed')),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${LocaleService.instance.t('stats_error')}: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchTreeData() async {
    try {
      final response = await _apiService.fetchTreeSurveyData();
      if (!mounted) return;
      setState(() {
        _treeData = response;
        _calculateCarbonMetrics();
      });
    } catch (e) {
      debugPrint('Error fetching tree data: $e');
    }
  }

  void _calculateCarbonMetrics() {
    double totalStorage = 0;
    double totalAnnual = 0;

    for (var tree in _treeData) {
      final species = tree['樹種名稱'] ?? '其他';
      final height = double.tryParse(tree['樹高（公尺）'].toString()) ?? 0.0;
      final dbh = double.tryParse(tree['胸徑（公分）'].toString()) ?? 0.0;

      // Storage: prefer DB-stored TIPC value; fall back to recompute via TIPC K_sp lookup
      final dbStorage = double.tryParse(
          (tree['碳儲存量'] ?? tree['carbon_storage'] ?? '').toString());
      final carbonStorage = dbStorage ??
          CarbonCalculationService.calculateCarbonStorage(species, height, dbh);

      // Annual: read DB-stored TIPC value only; client-side recompute is unsafe
      // because TIPC's annual formula is not publicly documented.
      // Backend SQL aliases the column as '推估年碳吸存量' (see routes/treeSurvey.js).
      final annualSequestration = double.tryParse(
              (tree['推估年碳吸存量'] ?? tree['carbon_sequestration_per_year'] ?? '')
                  .toString()) ??
          0.0;

      totalStorage += carbonStorage;
      totalAnnual += annualSequestration;
    }

    setState(() {
      _totalCarbonStorage = totalStorage;
      _totalAnnualSequestration = totalAnnual;
    });
  }

  // 截斷過長的標籤名稱
  String _truncateLabel(String label, {int maxLength = 6}) {
    if (label.length <= maxLength) return label;
    return '${label.substring(0, maxLength)}...';
  }

  Widget _buildChartCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required Widget chart,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 標題區域
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accentColor.withValues(alpha: 0.1),
                  accentColor.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: accentColor, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: accentColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 圖表區域
          Padding(
            padding: const EdgeInsets.all(16),
            child: chart,
          ),
        ],
      ),
    );
  }

  Widget _buildSpeciesChart() {
    if (_statistics == null || _statistics!['species'] == null) {
      return _buildEmptyState(LocaleService.instance.t('stats_empty_species'));
    }

    final speciesData = _statistics!['species'] as List;
    if (speciesData.isEmpty) return _buildEmptyState(LocaleService.instance.t('stats_empty_species'));
    
    final topSpecies = speciesData.take(8).toList(); // 減少到8個以避免擁擠
    final maxY = (topSpecies
        .map((e) => int.tryParse(e['count'].toString()) ?? 0)
        .reduce((a, b) => a > b ? a : b) * 1.2).toDouble();

    return _buildChartCard(
      title: LocaleService.instance.t('stats_species_title'),
      subtitle: LocaleService.instance.t('stats_species_sub'),
      icon: Icons.forest,
      accentColor: AppColors.forestGreen,
      chart: SizedBox(
        height: 280,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxY,
            barTouchData: BarTouchData(
              enabled: true,
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => AppColors.portBlue.withValues(alpha: 0.9),
                tooltipRoundedRadius: 8,
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final name = topSpecies[group.x.toInt()]['樹種名稱'];
                  return BarTooltipItem(
                    '$name\n${rod.toY.toInt()} 棵',
                    const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  );
                },
              ),
            ),
            titlesData: FlTitlesData(
              show: true,
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 60,
                  getTitlesWidget: (value, meta) {
                    if (value >= 0 && value < topSpecies.length) {
                      final name = topSpecies[value.toInt()]['樹種名稱'] ?? '';
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Transform.rotate(
                          angle: -0.5, // 旋轉標籤約30度
                          child: Text(
                            _truncateLabel(name),
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 45,
                  getTitlesWidget: (value, meta) {
                    return Text(
                      value.toInt().toString(),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    );
                  },
                ),
              ),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: maxY / 5,
              getDrawingHorizontalLine: (value) => FlLine(
                color: Colors.grey.shade200,
                strokeWidth: 1,
              ),
            ),
            borderData: FlBorderData(show: false),
            barGroups: List.generate(
              topSpecies.length,
              (index) => BarChartGroupData(
                x: index,
                barRods: [
                  BarChartRodData(
                    toY: (int.tryParse(topSpecies[index]['count'].toString()) ?? 0).toDouble(),
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [AppColors.forestGreen, AppColors.leafGreen],
                    ),
                    width: 22,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.analytics_outlined, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectChart() {
    if (_statistics == null || _statistics!['projects'] == null) {
      return _buildEmptyState(LocaleService.instance.t('stats_empty_project'));
    }

    final projectData = _statistics!['projects'] as List;
    if (projectData.isEmpty) return _buildEmptyState(LocaleService.instance.t('stats_empty_project'));
    
    final topProjects = projectData.take(6).toList(); // 減少到6個
    final maxY = (topProjects
        .map((e) => int.tryParse(e['count'].toString()) ?? 0)
        .reduce((a, b) => a > b ? a : b) * 1.2).toDouble();

    return _buildChartCard(
      title: LocaleService.instance.t('stats_project_title'),
      subtitle: LocaleService.instance.t('stats_project_sub'),
      icon: Icons.folder_special,
      accentColor: AppColors.portBlue,
      chart: SizedBox(
        height: 280,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxY,
            barTouchData: BarTouchData(
              enabled: true,
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => AppColors.portBlue.withValues(alpha: 0.9),
                tooltipRoundedRadius: 8,
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final name = topProjects[group.x.toInt()]['專案名稱'];
                  return BarTooltipItem(
                    '$name\n${rod.toY.toInt()} 棵',
                    const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  );
                },
              ),
            ),
            titlesData: FlTitlesData(
              show: true,
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 60,
                  getTitlesWidget: (value, meta) {
                    if (value >= 0 && value < topProjects.length) {
                      final name = topProjects[value.toInt()]['專案名稱'] ?? '';
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Transform.rotate(
                          angle: -0.5,
                          child: Text(
                            _truncateLabel(name, maxLength: 5),
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 45,
                  getTitlesWidget: (value, meta) {
                    return Text(
                      value.toInt().toString(),
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    );
                  },
                ),
              ),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: maxY / 5,
              getDrawingHorizontalLine: (value) => FlLine(
                color: Colors.grey.shade200,
                strokeWidth: 1,
              ),
            ),
            borderData: FlBorderData(show: false),
            barGroups: List.generate(
              topProjects.length,
              (index) => BarChartGroupData(
                x: index,
                barRods: [
                  BarChartRodData(
                    toY: (int.tryParse(topProjects[index]['count'].toString()) ?? 0).toDouble(),
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [AppColors.portBlue, AppColors.oceanCyan],
                    ),
                    width: 28,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAreaChart() {
    if (_statistics == null || _statistics!['areas'] == null) {
      return _buildEmptyState(LocaleService.instance.t('stats_empty_area'));
    }

    final areaData = _statistics!['areas'] as List;
    if (areaData.isEmpty) return _buildEmptyState(LocaleService.instance.t('stats_empty_area'));
    
    final topAreas = areaData.take(6).toList();
    final maxY = (topAreas
        .map((e) => int.tryParse(e['count'].toString()) ?? 0)
        .reduce((a, b) => a > b ? a : b) * 1.2).toDouble();

    return _buildChartCard(
      title: LocaleService.instance.t('stats_area_title'),
      subtitle: LocaleService.instance.t('stats_area_sub'),
      icon: Icons.location_on,
      accentColor: AppColors.warmOrange,
      chart: SizedBox(
        height: 280,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxY,
            barTouchData: BarTouchData(
              enabled: true,
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => AppColors.warmOrange.withValues(alpha: 0.9),
                tooltipRoundedRadius: 8,
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final name = topAreas[group.x.toInt()]['專案區位'];
                  return BarTooltipItem(
                    '$name\n${rod.toY.toInt()} 棵',
                    const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  );
                },
              ),
            ),
            titlesData: FlTitlesData(
              show: true,
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 60,
                  getTitlesWidget: (value, meta) {
                    if (value >= 0 && value < topAreas.length) {
                      final name = topAreas[value.toInt()]['專案區位'] ?? '';
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Transform.rotate(
                          angle: -0.5,
                          child: Text(
                            _truncateLabel(name, maxLength: 5),
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 45,
                  getTitlesWidget: (value, meta) {
                    return Text(
                      value.toInt().toString(),
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    );
                  },
                ),
              ),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: maxY / 5,
              getDrawingHorizontalLine: (value) => FlLine(
                color: Colors.grey.shade200,
                strokeWidth: 1,
              ),
            ),
            borderData: FlBorderData(show: false),
            barGroups: List.generate(
              topAreas.length,
              (index) => BarChartGroupData(
                x: index,
                barRods: [
                  BarChartRodData(
                    toY: (int.tryParse(topAreas[index]['count'].toString()) ?? 0).toDouble(),
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [AppColors.warmOrange, AppColors.sunYellow],
                    ),
                    width: 28,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSizeStats() {
    if (_statistics == null || _statistics!['sizes'] == null) {
      return _buildEmptyState(LocaleService.instance.t('stats_empty_size'));
    }

    final sizes = _statistics!['sizes'];

    String formatStat(dynamic value) {
      if (value == null) return 'N/A';
      final double? parsedValue = double.tryParse(value.toString());
      return parsedValue?.toStringAsFixed(2) ?? 'N/A';
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.creativePurple.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.creativePurple.withValues(alpha: 0.1),
                  AppColors.creativePurple.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.creativePurple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.straighten, color: AppColors.creativePurple, size: 24),
                ),
                const SizedBox(width: 16),
                Text(
                  LocaleService.instance.t('stats_size_title'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.creativePurple,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildModernStatRow(LocaleService.instance.t('stats_avg_height'), '${formatStat(sizes['avg_height'])} ${LocaleService.instance.t('stats_unit_m')}', Icons.height),
                _buildModernStatRow(LocaleService.instance.t('stats_max_height'), '${formatStat(sizes['max_height'])} ${LocaleService.instance.t('stats_unit_m')}', Icons.arrow_upward),
                _buildModernStatRow(LocaleService.instance.t('stats_min_height'), '${formatStat(sizes['min_height'])} ${LocaleService.instance.t('stats_unit_m')}', Icons.arrow_downward),
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  height: 1,
                  color: Colors.grey.shade200,
                ),
                _buildModernStatRow(LocaleService.instance.t('stats_avg_dbh'), '${formatStat(sizes['avg_dbh'])} ${LocaleService.instance.t('stats_unit_cm')}', Icons.circle_outlined),
                _buildModernStatRow(LocaleService.instance.t('stats_max_dbh'), '${formatStat(sizes['max_dbh'])} ${LocaleService.instance.t('stats_unit_cm')}', Icons.add_circle_outline),
                _buildModernStatRow(LocaleService.instance.t('stats_min_dbh'), '${formatStat(sizes['min_dbh'])} ${LocaleService.instance.t('stats_unit_cm')}', Icons.remove_circle_outline),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarbonStats() {
    if (_statistics == null || _statistics!['carbon'] == null) {
      return _buildEmptyState(LocaleService.instance.t('stats_empty_carbon'));
    }

    final carbon = _statistics!['carbon'];

    String formatStat(dynamic value) {
      if (value == null) return 'N/A';
      final double? parsedValue = double.tryParse(value.toString());
      return parsedValue?.toStringAsFixed(2) ?? 'N/A';
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.forestGreen.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.forestGreen.withValues(alpha: 0.1),
                  AppColors.forestGreen.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.forestGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.eco, color: AppColors.forestGreen, size: 24),
                ),
                const SizedBox(width: 16),
                Text(
                  LocaleService.instance.t('stats_carbon_title'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.forestGreen,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildModernStatRow('總碳儲存量', '${formatStat(carbon['total_carbon'])} 公斤', Icons.inventory_2),
                _buildModernStatRow('平均碳儲存量', '${formatStat(carbon['avg_carbon'])} 公斤', Icons.show_chart),
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  height: 1,
                  color: Colors.grey.shade200,
                ),
                _buildModernStatRow('總年碳吸存量', '${formatStat(carbon['total_annual_carbon'])} 公斤', Icons.trending_up),
                _buildModernStatRow('平均年碳吸存量', '${formatStat(carbon['avg_annual_carbon'])} 公斤', Icons.analytics),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernStatRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade500),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarbonOffsetCalculator() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF00897B), Color(0xFF00695C)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00897B).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.calculate, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        LocaleService.instance.t('stats_carbon_calc_title'),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        LocaleService.instance.t('stats_carbon_calc_sub'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildCarbonMetricCard(
                    icon: Icons.trending_up,
                    label: LocaleService.instance.t('stats_annual_seq_label'),
                    value: '${_totalAnnualSequestration.toStringAsFixed(1)}',
                    unit: 'kg CO₂',
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildCarbonMetricCard(
                    icon: Icons.inventory_2,
                    label: LocaleService.instance.t('stats_total_storage_label'),
                    value: '${_totalCarbonStorage.toStringAsFixed(1)}',
                    unit: 'kg CO₂',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCarbonMetricCard({
    required IconData icon,
    required String label,
    required String value,
    required String unit,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            unit,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.portBlue, Color(0xFF1565C0)],
            ),
          ),
        ),
        title: Text(
          LocaleService.instance.t('stats_title'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _fetchStatistics();
              _fetchTreeData();
            },
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.portBlue),
                    strokeWidth: 3,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    LocaleService.instance.t('stats_loading'),
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          : FadeTransition(
              opacity: _fadeAnimation,
              child: RefreshIndicator(
                onRefresh: () async {
                  await _fetchStatistics();
                  await _fetchTreeData();
                },
                color: AppColors.portBlue,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 頂部摘要卡片
                      _buildCarbonOffsetCalculator(),
                      const SizedBox(height: 8),
                      
                      // 圖表區域
                      _buildSpeciesChart(),
                      _buildProjectChart(),
                      _buildAreaChart(),
                      
                      // 統計數據區域
                      const SizedBox(height: 8),
                      _buildSizeStats(),
                      const SizedBox(height: 20),
                      _buildCarbonStats(),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
