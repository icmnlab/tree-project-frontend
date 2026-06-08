import '../widgets/field/field_session_setup.dart';

/// 全 App 統一的「專案／區」工作範圍（UI 語意）。
///
/// | UI | 本模型欄位 | DB / 現場欄位 |
/// |----|-----------|---------------|
/// | **專案** | [programName] | `project_location`, `project_areas.area_name`, `FieldSessionSetup.projectArea` |
/// | **區** | [blockName] | `project_name`, `projects.name`, `FieldSessionSetup.projectName` |
/// | 代碼 | [projectCode] | `projects.project_code`（穩定主鍵） |
class ProjectScope {
  final String programName;
  final String blockName;
  final String projectCode;

  const ProjectScope({
    required this.programName,
    required this.blockName,
    required this.projectCode,
  });

  bool get isComplete =>
      programName.trim().isNotEmpty &&
      blockName.trim().isNotEmpty &&
      projectCode.trim().isNotEmpty;

  /// 與現場 BLE／pending 相容的 [FieldSessionSetup]
  FieldSessionSetup toFieldSessionSetup({
    required String batchName,
    String gpsSource = 'tree',
  }) {
    return FieldSessionSetup(
      batchName: batchName,
      projectArea: programName.trim(),
      projectName: blockName.trim(),
      projectCode: projectCode.trim(),
      gpsSource: gpsSource,
    );
  }

  factory ProjectScope.fromFieldSessionSetup(FieldSessionSetup setup) {
    return ProjectScope(
      programName: setup.projectArea,
      blockName: setup.projectName,
      projectCode: setup.projectCode,
    );
  }

  factory ProjectScope.fromJson(Map<String, dynamic> json) {
    final domain = json['domain'];
    if (domain is Map) {
      return ProjectScope(
        programName: (domain['program'] ?? domain['program_name'] ?? '')
            .toString(),
        blockName: (domain['block'] ?? domain['block_name'] ?? '').toString(),
        projectCode: (domain['project_code'] ?? json['project_code'] ?? '')
            .toString(),
      );
    }
    return ProjectScope(
      programName: (json['program_name'] ??
              json['project_location'] ??
              json['專案區位'] ??
              json['projectArea'] ??
              '')
          .toString(),
      blockName: (json['block_name'] ??
              json['project_name'] ??
              json['專案名稱'] ??
              json['projectName'] ??
              json['name'] ??
              '')
          .toString(),
      projectCode: (json['project_code'] ?? json['code'] ?? json['專案代碼'] ?? '')
          .toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'programName': programName,
        'blockName': blockName,
        'projectCode': projectCode,
      };

  @override
  bool operator ==(Object other) =>
      other is ProjectScope &&
      other.programName == programName &&
      other.blockName == blockName &&
      other.projectCode == projectCode;

  @override
  int get hashCode => Object.hash(programName, blockName, projectCode);

  String get displayLabel => '$programName · $blockName ($projectCode)';
}
