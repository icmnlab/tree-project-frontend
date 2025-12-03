import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../models/tree_species.dart';
import '../services/tree_service.dart';
import '../widgets/species_card.dart';
import '../widgets/custom_dropdown.dart';

class CarbonSinkAssistant extends StatefulWidget {
  const CarbonSinkAssistant({Key? key}) : super(key: key);

  @override
  _CarbonSinkAssistantState createState() => _CarbonSinkAssistantState();
}

class _CarbonSinkAssistantState extends State<CarbonSinkAssistant>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TreeService _treeService = TreeService();
  bool _isLoading = true;

  // 單一樹種碳吸收計算相關變量
  String? _selectedSpeciesId;
  int _treeAge = 10;
  int _treeQuantity = 1;
  double _carbonAbsorption = 0;

  // 總碳吸收計算相關變量
  final List<Map<String, dynamic>> _selectedTrees = [];
  Map<String, dynamic>? _totalCarbonResult;

  // 地區推薦相關變量
  String? _selectedRegion;
  List<TreeSpecies> _recommendedSpecies = [];

  // 效率篩選相關變量
  int _efficiencyAge = 20;
  List<TreeSpecies> _efficientSpecies = [];

  // 環境條件篩選相關變量
  final Map<String, dynamic> _environmentConditions = {
    'soil_type': '砂質壤土',
    'annual_rainfall': 2000.0,
    'temperature_min': 15.0,
  };
  // ignore: unused_field
  List<TreeSpecies> _environmentallyFilteredSpecies = []; // Reserved for environment filtering

  // 混合造林推薦相關變量
  String? _mixedForestRegion;
  int _totalArea = 100; // 默認100公頃
  Map<String, dynamic>? _mixedForestResult;

  // 台灣地區列表
  final List<String> _taiwanRegions = ['北部地區', '中部地區', '南部地區', '東部地區', '離島地區'];

  // 土壤類型列表
  final List<String> _soilTypes = ['砂質壤土', '粘土', '壤土', '石灰質土壤', '酸性土壤'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    await _treeService.loadTreeSpecies();

    setState(() {
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // 計算單一樹種碳吸收量
  void _calculateSingleSpeciesCarbon() {
    if (_selectedSpeciesId == null) return;

    setState(() {
      _carbonAbsorption = _treeService.calculateSpeciesCarbon(
          _selectedSpeciesId!, _treeAge, _treeQuantity);
    });
  }

  // 添加樹種到總計算列表
  void _addTreeToTotal() {
    if (_selectedSpeciesId == null) return;

    final TreeSpecies? species =
        _treeService.getSpeciesById(_selectedSpeciesId!);
    if (species == null) return;

    setState(() {
      _selectedTrees.add({
        'id': species.id,
        'name': species.name,
        'age': _treeAge,
        'quantity': _treeQuantity,
      });
    });
  }

  // 計算總碳吸收量
  void _calculateTotalCarbon() {
    if (_selectedTrees.isEmpty) return;

    // 轉換為TreeService所需的格式
    final Map<String, Map<String, dynamic>> treesData = {};
    for (final tree in _selectedTrees) {
      treesData[tree['id']] = {
        'age': tree['age'],
        'quantity': tree['quantity'],
      };
    }

    setState(() {
      _totalCarbonResult = _treeService.calculateTotalCarbon(treesData);
    });
  }

  // 根據地區推薦樹種
  void _recommendTreesByRegion() {
    if (_selectedRegion == null) return;

    setState(() {
      _recommendedSpecies = _treeService.recommendByRegion(_selectedRegion!);
    });
  }

  // 按碳吸收效率篩選樹種
  void _filterTreesByEfficiency() {
    setState(() {
      _efficientSpecies = _treeService.filterByEfficiency(_efficiencyAge);
    });
  }

  // 按環境條件篩選樹種 - 保留供未來使用
  // ignore: unused_element
  void _filterTreesByEnvironment() {
    setState(() {
      _environmentallyFilteredSpecies =
          _treeService.filterByEnvironment(_environmentConditions);
    });
  }

  // 生成混合造林推薦
  void _generateMixedForest() {
    if (_mixedForestRegion == null) return;

    setState(() {
      _mixedForestResult = _treeService.generateMixedForest(
          _mixedForestRegion!, _environmentConditions, _totalArea);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI永續碳匯助手'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: '單一樹種碳吸收'),
            Tab(text: '總碳吸收計算'),
            Tab(text: '地區樹種推薦'),
            Tab(text: '碳效率篩選'),
            Tab(text: '混合造林推薦'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSingleSpeciesCalculator(),
          _buildTotalCarbonCalculator(),
          _buildRegionalRecommendation(),
          _buildEfficiencyFilter(),
          _buildMixedForestRecommendation(),
        ],
      ),
    );
  }

  // 功能1：單一樹種碳吸收計算界面
  Widget _buildSingleSpeciesCalculator() {
    final allSpecies = _treeService.getAllSpecies();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomDropdown<String>(
            label: '選擇樹種',
            items: allSpecies
                .map((species) => {
                      'value': species.id,
                      'label': species.name,
                    })
                .toList(),
            selectedValue: _selectedSpeciesId,
            onChanged: (value) {
              setState(() {
                _selectedSpeciesId = value;
              });
            },
          ),
          const SizedBox(height: 16),
          const Text('樹齡（年）：'),
          Slider(
            value: _treeAge.toDouble(),
            min: 1,
            max: 100,
            divisions: 99,
            label: _treeAge.toString(),
            onChanged: (value) {
              setState(() {
                _treeAge = value.round();
              });
            },
          ),
          Text('選擇樹齡：$_treeAge 年'),
          const SizedBox(height: 16),
          const Text('樹木數量：'),
          Slider(
            value: _treeQuantity.toDouble(),
            min: 1,
            max: 1000,
            divisions: 999,
            label: _treeQuantity.toString(),
            onChanged: (value) {
              setState(() {
                _treeQuantity = value.round();
              });
            },
          ),
          Text('選擇數量：$_treeQuantity 棵'),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _selectedSpeciesId != null
                ? _calculateSingleSpeciesCarbon
                : null,
            child: const Text('計算碳吸收量'),
          ),
          const SizedBox(height: 24),
          if (_carbonAbsorption > 0)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '計算結果',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '每年總碳吸收量: ${_carbonAbsorption.toStringAsFixed(2)} kg CO₂',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '30年累計碳吸收量: ${(_carbonAbsorption * 30).toStringAsFixed(2)} kg CO₂',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // 功能2：總碳吸收計算界面
  Widget _buildTotalCarbonCalculator() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '添加樹種到計算列表',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          CustomDropdown<String>(
            label: '選擇樹種',
            items: _treeService
                .getAllSpecies()
                .map((species) => {
                      'value': species.id,
                      'label': species.name,
                    })
                .toList(),
            selectedValue: _selectedSpeciesId,
            onChanged: (value) {
              setState(() {
                _selectedSpeciesId = value;
              });
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '樹齡（年）',
                  ),
                  onChanged: (value) {
                    setState(() {
                      _treeAge = int.tryParse(value) ?? 10;
                    });
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '數量（棵）',
                  ),
                  onChanged: (value) {
                    setState(() {
                      _treeQuantity = int.tryParse(value) ?? 1;
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _selectedSpeciesId != null ? _addTreeToTotal : null,
            child: const Text('添加到計算列表'),
          ),
          const SizedBox(height: 24),
          if (_selectedTrees.isNotEmpty) ...[
            const Text(
              '已選樹種列表',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _selectedTrees.length,
                itemBuilder: (context, index) {
                  final tree = _selectedTrees[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(tree['name']),
                      subtitle:
                          Text('樹齡: ${tree['age']}年, 數量: ${tree['quantity']}棵'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          setState(() {
                            _selectedTrees.removeAt(index);
                            _totalCarbonResult = null; // 清除上次計算結果
                          });
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed:
                  _selectedTrees.isNotEmpty ? _calculateTotalCarbon : null,
              child: const Text('計算總碳吸收量'),
            ),
            if (_totalCarbonResult != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '計算結果',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '每年總碳吸收量: ${_totalCarbonResult!['totalCarbon'].toStringAsFixed(2)} kg CO₂',
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '各樹種貢獻：',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._totalCarbonResult!['speciesContribution']
                          .entries
                          .map(
                            (entry) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '${entry.key}: ${entry.value.toStringAsFixed(2)} kg CO₂',
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          )
                          .toList(),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // 功能3：地區樹種推薦界面
  Widget _buildRegionalRecommendation() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '地區樹種推薦',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          CustomDropdown<String>(
            label: '選擇地區',
            items: _taiwanRegions
                .map((region) => {
                      'value': region,
                      'label': region,
                    })
                .toList(),
            selectedValue: _selectedRegion,
            onChanged: (value) {
              setState(() {
                _selectedRegion = value;
              });
            },
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _selectedRegion != null ? _recommendTreesByRegion : null,
            child: const Text('查詢推薦樹種'),
          ),
          const SizedBox(height: 24),
          if (_recommendedSpecies.isNotEmpty) ...[
            Text(
              '${_selectedRegion!}適合栽種的樹種',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _recommendedSpecies.length,
                itemBuilder: (context, index) {
                  final species = _recommendedSpecies[index];
                  return SpeciesCard(species: species);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  // 功能4：碳效率篩選界面
  Widget _buildEfficiencyFilter() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '按碳吸收效率篩選樹種',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          const Text('選擇樹齡（年）：'),
          Slider(
            value: _efficiencyAge.toDouble(),
            min: 1,
            max: 100,
            divisions: 99,
            label: _efficiencyAge.toString(),
            onChanged: (value) {
              setState(() {
                _efficiencyAge = value.round();
              });
            },
          ),
          Text('樹齡：$_efficiencyAge 年'),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _filterTreesByEfficiency,
            child: const Text('找出碳吸收效率最高的樹種'),
          ),
          const SizedBox(height: 24),
          if (_efficientSpecies.isNotEmpty) ...[
            Text(
              '$_efficiencyAge 年樹齡碳吸收效率最高的樹種',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _efficientSpecies.length,
                itemBuilder: (context, index) {
                  final species = _efficientSpecies[index];
                  final efficiency =
                      species.calculateCarbonAbsorption(_efficiencyAge);

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: AppColors.primary,
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      species.name,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      species.scientificName,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontStyle: FontStyle.italic,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '碳吸收效率: ${efficiency.toStringAsFixed(2)} kg CO₂/年',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '適合地區: ${species.suitableRegions.join(", ")}',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  // 功能5：混合造林推薦界面
  Widget _buildMixedForestRecommendation() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '混合造林推薦',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          CustomDropdown<String>(
            label: '選擇地區',
            items: _taiwanRegions
                .map((region) => {
                      'value': region,
                      'label': region,
                    })
                .toList(),
            selectedValue: _mixedForestRegion,
            onChanged: (value) {
              setState(() {
                _mixedForestRegion = value;
              });
            },
          ),
          const SizedBox(height: 16),
          CustomDropdown<String>(
            label: '土壤類型',
            items: _soilTypes
                .map((type) => {
                      'value': type,
                      'label': type,
                    })
                .toList(),
            selectedValue: _environmentConditions['soil_type'],
            onChanged: (value) {
              setState(() {
                _environmentConditions['soil_type'] = value;
              });
            },
          ),
          const SizedBox(height: 16),
          TextField(
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '年平均降雨量 (mm)',
            ),
            onChanged: (value) {
              setState(() {
                _environmentConditions['annual_rainfall'] =
                    double.tryParse(value) ?? 2000.0;
              });
            },
          ),
          const SizedBox(height: 16),
          TextField(
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '最低溫度 (°C)',
            ),
            onChanged: (value) {
              setState(() {
                _environmentConditions['temperature_min'] =
                    double.tryParse(value) ?? 15.0;
              });
            },
          ),
          const SizedBox(height: 16),
          TextField(
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '造林總面積 (公頃)',
            ),
            onChanged: (value) {
              setState(() {
                _totalArea = int.tryParse(value) ?? 100;
              });
            },
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _mixedForestRegion != null ? _generateMixedForest : null,
            child: const Text('生成混合造林推薦'),
          ),
          const SizedBox(height: 24),
          if (_mixedForestResult != null) ...[
            if (_mixedForestResult!['success']) ...[
              const Text(
                '混合造林推薦結果',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '總面積: ${_mixedForestResult!['totalArea']} 公頃',
                style: const TextStyle(fontSize: 16),
              ),
              Text(
                '30年總碳吸收量: ${_mixedForestResult!['totalCarbon30yr'].toStringAsFixed(2)} kg CO₂',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              const Text(
                '推薦種植組合：',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: _mixedForestResult!['recommendation'].length,
                  itemBuilder: (context, index) {
                    final entry = _mixedForestResult!['recommendation']
                        .entries
                        .elementAt(index);
                    final treeName = entry.key;
                    final data = entry.value;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              treeName,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '分配面積: ${data['area'].toStringAsFixed(1)} 公頃 (${(data['proportion'] * 100).toStringAsFixed(1)}%)',
                              style: const TextStyle(fontSize: 14),
                            ),
                            Text(
                              '30年碳吸收量: ${data['estimated_carbon_30yr'].toStringAsFixed(2)} kg CO₂',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ] else ...[
              Card(
                color: Colors.amber[100],
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const Icon(Icons.warning, color: Colors.amber),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(_mixedForestResult!['message']),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
