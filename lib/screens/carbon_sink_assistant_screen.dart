import 'package:flutter/material.dart';
import '../models/tree_species.dart';
// TreeService import removed - available via TreeService() when needed
import '../services/carbon_sink_service.dart';
import '../constants/colors.dart';

class CarbonSinkAssistantScreen extends StatefulWidget {
  const CarbonSinkAssistantScreen({Key? key}) : super(key: key);

  @override
  _CarbonSinkAssistantScreenState createState() =>
      _CarbonSinkAssistantScreenState();
}

class _CarbonSinkAssistantScreenState extends State<CarbonSinkAssistantScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  // TreeService available via TreeService() when needed
  final CarbonSinkService _carbonSinkService = CarbonSinkService();

  // 樹種相關變量
  List<TreeSpecies> _allSpecies = [];
  List<TreeSpecies> _filteredSpecies = [];
  TreeSpecies? _selectedSpecies;

  // 篩選參數
  String? _selectedRegion;
  double _minEfficiency = 0.0;
  String? _selectedSoilType;
  String? _selectedSunExposure;

  // 碳計算參數
  int _treeCount = 10;
  int _treeAge = 5;
  double _calculatedCarbon = 0.0;

  // 混合造林參數
  int _desiredSpeciesCount = 3;
  List<TreeSpecies> _recommendedMix = [];

  // 選項列表
  final List<String> _regions = ['北部', '中部', '南部', '東部', '離島'];
  final List<String> _soilTypes = ['沙質土', '黏土', '壤土', '酸性土', '鹼性土'];
  final List<String> _sunExposures = ['全日照', '半日照', '遮蔭'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await _carbonSinkService.initialize();
    setState(() {
      _allSpecies = _carbonSinkService.getAllSpecies();
      _filteredSpecies = _allSpecies;
    });
  }

  // 更新篩選的樹種
  void _updateFilteredSpecies() {
    setState(() {
      // 初始化為所有樹種
      _filteredSpecies = _allSpecies;

      // 根據地區篩選
      if (_selectedRegion != null) {
        _filteredSpecies =
            _carbonSinkService.recommendByRegion(_selectedRegion!);
      }

      // 根據效率篩選
      if (_minEfficiency > 0) {
        _filteredSpecies =
            _carbonSinkService.filterByEfficiency(_minEfficiency);
      }

      // 根據環境條件篩選
      if (_selectedSoilType != null || _selectedSunExposure != null) {
        _filteredSpecies = _carbonSinkService.filterByEnvironment(
          soilType: _selectedSoilType,
          sunExposure: _selectedSunExposure,
        );
      }
    });
  }

  // 計算特定樹種碳吸收量
  void _calculateCarbon() {
    if (_selectedSpecies == null) return;

    setState(() {
      _calculatedCarbon = _carbonSinkService.calculateTotalCarbon(
        _selectedSpecies!.id,
        _treeCount,
        _treeAge,
      );
    });
  }

  // 生成混合造林推薦
  void _generateMixedForest() {
    if (_selectedRegion == null) return;

    setState(() {
      _recommendedMix = _carbonSinkService.generateMixedForest(
        region: _selectedRegion!,
        desiredSpeciesCount: _desiredSpeciesCount,
        minEfficiency: _minEfficiency,
        soilType: _selectedSoilType,
        sunExposure: _selectedSunExposure,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI永續碳匯助手'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '樹種篩選'),
            Tab(text: '碳計算器'),
            Tab(text: '混合造林'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFilterTab(),
          _buildCalculatorTab(),
          _buildMixedForestTab(),
        ],
      ),
    );
  }

  // 樹種篩選標籤頁
  Widget _buildFilterTab() {
    return _allSpecies.isEmpty
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '篩選條件',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),

                        // 地區選擇
                        DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                            labelText: '地區',
                            border: OutlineInputBorder(),
                          ),
                          value: _selectedRegion,
                          items: _regions
                              .map((region) => DropdownMenuItem(
                                    value: region,
                                    child: Text(region),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedRegion = value;
                            });
                            _updateFilteredSpecies();
                          },
                        ),
                        const SizedBox(height: 16),

                        // 效率滑桿
                        Text('最低碳吸收效率: ${_minEfficiency.toStringAsFixed(1)}'),
                        Slider(
                          value: _minEfficiency,
                          min: 0,
                          max: 10,
                          divisions: 100,
                          onChanged: (value) {
                            setState(() {
                              _minEfficiency = value;
                            });
                          },
                          onChangeEnd: (value) {
                            _updateFilteredSpecies();
                          },
                        ),
                        const SizedBox(height: 16),

                        // 土壤類型
                        DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                            labelText: '土壤類型',
                            border: OutlineInputBorder(),
                          ),
                          value: _selectedSoilType,
                          items: _soilTypes
                              .map((type) => DropdownMenuItem(
                                    value: type,
                                    child: Text(type),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedSoilType = value;
                            });
                            _updateFilteredSpecies();
                          },
                        ),
                        const SizedBox(height: 16),

                        // 日照條件
                        DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                            labelText: '日照條件',
                            border: OutlineInputBorder(),
                          ),
                          value: _selectedSunExposure,
                          items: _sunExposures
                              .map((exposure) => DropdownMenuItem(
                                    value: exposure,
                                    child: Text(exposure),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedSunExposure = value;
                            });
                            _updateFilteredSpecies();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 篩選結果
                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '符合條件的樹種: ${_filteredSpecies.length}',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),

                        // 樹種列表
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _filteredSpecies.length,
                          itemBuilder: (context, index) {
                            final species = _filteredSpecies[index];
                            return Card(
                              child: ListTile(
                                title: Text(species.name),
                                subtitle: Text(
                                  '碳效率: ${species.carbonEfficiency.toStringAsFixed(1)} | 土壤: ${species.soilType} | 日照: ${species.sunExposure}',
                                ),
                                onTap: () {
                                  setState(() {
                                    _selectedSpecies = species;
                                  });
                                  _calculateCarbon();
                                  _tabController.animateTo(1); // 跳轉到計算器標籤頁
                                },
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
  }

  // 碳計算器標籤頁
  Widget _buildCalculatorTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Card(
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '碳吸收計算器',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              // 選擇的樹種
              Text(
                '選擇的樹種: ${_selectedSpecies?.name ?? '未選擇'}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              if (_selectedSpecies == null)
                const Text('請先在樹種篩選頁面選擇一個樹種')
              else
                Column(
                  children: [
                    // 樹木數量
                    Row(
                      children: [
                        const Text('樹木數量: '),
                        Expanded(
                          child: Slider(
                            value: _treeCount.toDouble(),
                            min: 1,
                            max: 1000,
                            divisions: 999,
                            onChanged: (value) {
                              setState(() {
                                _treeCount = value.toInt();
                              });
                              _calculateCarbon();
                            },
                          ),
                        ),
                        Text('$_treeCount'),
                      ],
                    ),

                    // 樹齡
                    Row(
                      children: [
                        const Text('樹齡(年): '),
                        Expanded(
                          child: Slider(
                            value: _treeAge.toDouble(),
                            min: 1,
                            max: 100,
                            divisions: 99,
                            onChanged: (value) {
                              setState(() {
                                _treeAge = value.toInt();
                              });
                              _calculateCarbon();
                            },
                          ),
                        ),
                        Text('$_treeAge'),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // 計算結果
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '單株碳吸收量(kg/年):',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                (_calculatedCarbon / _treeCount)
                                    .toStringAsFixed(2),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '總碳吸收量(kg/年):',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                _calculatedCarbon.toStringAsFixed(2),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                        ],
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

  // 混合造林標籤頁
  Widget _buildMixedForestTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Card(
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '混合造林推薦',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              // 提示選擇地區
              if (_selectedRegion == null)
                const Text('請先在樹種篩選頁面選擇地區')
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('已選擇地區: $_selectedRegion'),
                    const SizedBox(height: 16),

                    // 樹種數量
                    Row(
                      children: [
                        const Text('推薦樹種數量: '),
                        Expanded(
                          child: Slider(
                            value: _desiredSpeciesCount.toDouble(),
                            min: 1,
                            max: 10,
                            divisions: 9,
                            onChanged: (value) {
                              setState(() {
                                _desiredSpeciesCount = value.toInt();
                              });
                            },
                          ),
                        ),
                        Text('$_desiredSpeciesCount'),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 生成按鈕
                    Center(
                      child: ElevatedButton(
                        onPressed: _generateMixedForest,
                        child: const Text('生成混合造林推薦'),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 24),

              // 推薦結果
              if (_recommendedMix.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '推薦樹種組合',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    const SizedBox(height: 8),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _recommendedMix.length,
                      itemBuilder: (context, index) {
                        final species = _recommendedMix[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            title: Text(species.name),
                            subtitle: Text(
                              '碳效率: ${species.carbonEfficiency.toStringAsFixed(1)} | 土壤: ${species.soilType} | 日照: ${species.sunExposure}',
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
