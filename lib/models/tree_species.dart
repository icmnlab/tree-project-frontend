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
      id: json['id'],
      name: json['name'],
      scientificName: json['scientificName'],
      carbonEfficiency: json['carbonEfficiency'].toDouble(),
      soilType: json['soilType'],
      sunExposure: json['sunExposure'],
      minTemperature: json['minTemperature'].toDouble(),
      maxTemperature: json['maxTemperature'].toDouble(),
      suitableRegions: List<String>.from(json['suitableRegions']),
      description: json['description'],
      carbonAbsorptionRate: json['carbonAbsorptionRate'].toDouble(),
    );
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
