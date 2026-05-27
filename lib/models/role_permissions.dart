/// 角色權限對照表（與後端 roleAuth.js、前端 AuthService 對齊）
class RolePermissionEntry {
  final String role;
  final int level;
  final String summary;
  final List<String> capabilities;
  final List<String> restrictions;

  const RolePermissionEntry({
    required this.role,
    required this.level,
    required this.summary,
    required this.capabilities,
    this.restrictions = const [],
  });
}

class RolePermissions {
  static const rolesHighToLow = [
    '系統管理員',
    '業務管理員',
    '專案管理員',
    '調查管理員',
    '一般使用者',
  ];

  static const entries = <RolePermissionEntry>[
    RolePermissionEntry(
      role: '系統管理員',
      level: 5,
      summary: '全域最高權限，可管理所有帳號與系統維運。',
      capabilities: [
        '存取管理後台全部功能',
        '資料庫備份／還原',
        '執行後端維運腳本',
        '管理 API 金鑰',
        '管理 IP 黑名單',
        '管理所有使用者（含其他系統管理員）',
        '管理邀請碼、稽核 log、待重設密碼',
        '存取所有專案資料',
        '繪製／刪除專案邊界',
        'CSV 匯入、刪除專案',
        '新增／編輯／刪除樹木',
      ],
      restrictions: [
        '不可透過 API 刪除自己的帳號',
      ],
    ),
    RolePermissionEntry(
      role: '業務管理員',
      level: 4,
      summary: '負責使用者、邀請碼與跨專案資料管理。',
      capabilities: [
        '存取管理後台（使用者、匯出、專案管理、維運工具箱）',
        '新增／編輯／停用使用者、指派專案權限',
        '建立與停用邀請碼',
        '查看稽核 log、待重設密碼',
        'CSV 匯入',
        '新增專案（需先選定專案區位）',
        '刪除專案',
        '存取所有已授權專案資料',
        '繪製／刪除專案邊界',
        '新增／編輯／刪除樹木',
      ],
      restrictions: [
        '無法備份／還原資料庫',
        '無法管理 API 金鑰、IP 黑名單',
        '僅能管理權限低於自己的帳號',
      ],
    ),
    RolePermissionEntry(
      role: '專案管理員',
      level: 3,
      summary: '管理自己負責專案的邊界、區域與刪除作業。',
      capabilities: [
        '存取管理後台（依 tab 權限：專案邊界繪製）',
        '繪製／更新／刪除專案邊界',
        '刪除樹木、匯入樹木檔案',
        '新增／編輯樹木（限已授權專案）',
        '查看已授權專案資料',
      ],
      restrictions: [
        '無法管理使用者、邀請碼',
        '無法新增專案、CSV 匯入、刪除整個專案',
        '無法存取系統維運（備份、API 金鑰、IP 黑名單）',
      ],
    ),
    RolePermissionEntry(
      role: '調查管理員',
      level: 2,
      summary: '現場調查：新增與編輯樹木、匯入匯出（限已授權專案）。',
      capabilities: [
        '新增／編輯樹木（V2/V3、現場連線、待測量）',
        '批次匯入樹木',
        '使用 AI 永續報告等功能',
        '查看已授權專案資料',
      ],
      restrictions: [
        '無法刪除樹木或專案',
        '無法繪製專案邊界、新增專案',
        '無法進入管理後台（需系統管理員）',
      ],
    ),
    RolePermissionEntry(
      role: '一般使用者',
      level: 1,
      summary: '僅能查看已授權專案的資料。',
      capabilities: [
        '登入 App，查看地圖、樹木列表、統計（限已授權專案）',
      ],
      restrictions: [
        '無法新增或編輯樹木',
        '無法進入管理後台',
        '無法管理專案或使用者',
      ],
    ),
  ];

  static RolePermissionEntry? forRole(String role) {
    for (final e in entries) {
      if (e.role == role) return e;
    }
    return null;
  }
}
