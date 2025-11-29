class TreeSpecies {
  final String id;
  final String name;
  final String scientificName;
  final double carbonEfficiency;
  final String soilType;
  final String sunExposure;
  final double minTemperature;
  final double maxTemperature;
  final List<String> suitableRegions;
  final String description;
  final double carbonAbsorptionRate;

  TreeSpecies({
    required this.id,
    required this.name,
    required this.scientificName,
    required this.carbonEfficiency,
    required this.soilType,
    required this.sunExposure,
    required this.minTemperature,
    required this.maxTemperature,
    required this.suitableRegions,
    required this.description,
    required this.carbonAbsorptionRate,
  });

  factory TreeSpecies.fromJson(Map<String, dynamic> json) {
    return TreeSpecies(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '未知樹種',
      scientificName: json['scientificName']?.toString() ?? '',
      carbonEfficiency: _parseDouble(json['carbonEfficiency']),
      soilType: json['soilType']?.toString() ?? '壤土',
      sunExposure: json['sunExposure']?.toString() ?? '全日照',
      minTemperature: _parseDouble(json['minTemperature'], defaultValue: 10.0),
      maxTemperature: _parseDouble(json['maxTemperature'], defaultValue: 35.0),
      suitableRegions: json['suitableRegions'] != null
          ? List<String>.from(json['suitableRegions'])
          : <String>[],
      description: json['description']?.toString() ?? '',
      carbonAbsorptionRate: _parseDouble(json['carbonAbsorptionRate']),
    );
  }

  static double _parseDouble(dynamic value, {double defaultValue = 0.0}) {
    if (value == null) return defaultValue;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'scientificName': scientificName,
      'carbonEfficiency': carbonEfficiency,
      'soilType': soilType,
      'sunExposure': sunExposure,
      'minTemperature': minTemperature,
      'maxTemperature': maxTemperature,
      'suitableRegions': suitableRegions,
      'description': description,
      'carbonAbsorptionRate': carbonAbsorptionRate,
    };
  }

  // 計算碳吸收量的方法
  double calculateCarbonAbsorption(int age) {
    return carbonAbsorptionRate * age;
  }
}
