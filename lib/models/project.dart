class Project {
  final String code;
  final String name;
  final String? area;

  Project({required this.code, required this.name, this.area});

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      code: (json['code'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      area: json['area']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'name': name,
      'area': area,
    };
  }
}
