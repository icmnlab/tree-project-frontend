import 'generated/tipc_kp_lookup.g.dart';

/// Carbon storage calculator aligned with the TIPC platform.
///
/// Methodology — 環境部 AR-TMS0001 / 林業署森林碳匯調查與監測手冊式 6-4:
///   carbon_storage_kg = round(K_sp · DBH_cm² · H_m, 2)
///   K_sp = F · (π/4) · BEF · (1+R) · CF · (44/12) · 0.1 · D_wood
///
/// Constants (from TIPC reverse engineering, validated against 7044 rows):
///   F          = 0.45 broadleaf | 0.50 conifer   stem form factor
///   π/4 ≈ 0.79  cross-section coefficient
///   BEF        = 1.40                            biomass expansion factor
///   R          = 0.24                            root-to-shoot ratio
///   CF         = 0.4691                          carbon fraction
///   44/12 ≈ 3.667                                CO₂ / C molar ratio
///   0.1                                          unit factor (cm²·m → m³, t → kg)
///   D_wood     = species basic specific gravity (oven-dry / green volume)
///
/// Per-species K_sp values are recovered from
/// `backend/database/initial_data/tree_survey_data.csv` and embedded in
/// [kTipcKspLookup] (see `generated/tipc_kp_lookup.g.dart`).
///
/// Annual sequestration is **not computed client-side**: the TIPC platform
/// uses an internal formula incorporating tree age that is not publicly
/// documented. UI should display the DB-stored
/// `carbon_sequestration_per_year` value, or "—" when absent.
///
/// References:
///   [1] 環境部 (2023). 溫室氣體減量方法學 AR-TMS0001 造林與植林碳匯專案.
///   [2] 農業部林業及自然保育署 (2024). 森林碳匯調查與監測手冊, 表 6-4.
class CarbonCalculationService {
  /// Look up the TIPC K_sp coefficient for [species]. Falls back to the
  /// broadleaf default (D_wood = 0.530) when the species is unknown, or to
  /// the conifer default when [species] matches a known conifer name.
  static double getKsp(String species) {
    final entry = _findEntry(species);
    if (entry != null) return entry.kSp;
    return kTipcConiferNames.contains(species)
        ? kTipcDefaultKspConifer
        : kTipcDefaultKspBroadleaf;
  }

  /// Provenance tag (`tipc_reverse_engineered`, `tipc_default_0.530`,
  /// `tipc_non_uniform_median`, or `default_fallback`).
  static String getKspSource(String species) {
    final entry = _findEntry(species);
    if (entry != null) return entry.source;
    return 'default_fallback';
  }

  static TipcKspEntry? _findEntry(String species) {
    if (species.isEmpty) return null;
    final hit = kTipcKspLookup[species];
    if (hit != null) return hit;
    // Tolerant match (e.g., '台灣欒樹' vs '臺灣欒樹')
    for (final entry in kTipcKspLookup.entries) {
      if (entry.key.contains(species) || species.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  /// Compute carbon storage in kg CO₂.
  ///
  /// Returns 0 when [dbh] or [height] are non-positive: the TIPC formula
  /// requires both DBH and tree height; without height we cannot produce a
  /// number consistent with the TIPC platform output.
  static double calculateCarbonStorage(
      String species, double height, double dbh) {
    if (dbh <= 0 || height <= 0) return 0;
    final kSp = getKsp(species);
    final raw = kSp * dbh * dbh * height;
    // Match TIPC rounding (2 decimals)
    return double.parse(raw.toStringAsFixed(2));
  }

  /// **Deprecated.** Always returns 0.
  ///
  /// The TIPC platform's annual sequestration formula is not publicly
  /// documented and depends on tree age in a non-trivial way. UI must read
  /// the persisted `carbon_sequestration_per_year` field directly and show
  /// "—" when absent. Kept for source-compatibility with existing callers.
  @Deprecated('Read carbon_sequestration_per_year from DB instead. '
      'TIPC annual formula is not publicly available; client-side '
      'recomputation is unsafe.')
  static double calculateAnnualCarbonSequestration(
      String species, double height, double dbh, int ageYears) {
    return 0;
  }

  // 計算抵換碳足跡所需樹木數量。
  // Requires [annualPerTree] (kg CO₂/年) supplied by caller — usually the
  // average of DB-stored `carbon_sequestration_per_year` for a project area.
  static int calculateTreesNeededForOffset(
      double carbonFootprint, double annualPerTree) {
    if (annualPerTree <= 0) return 0;
    return (carbonFootprint / annualPerTree).ceil();
  }

  // 計算碳足跡（簡易版）
  static double calculateCarbonFootprint({
    double electricityKwh = 0,
    double gasolineLiters = 0,
    double dieselLiters = 0,
    double naturalGasCubicMeters = 0,
    double waterCubicMeters = 0,
    double carKilometers = 0,
    double motorcycleKilometers = 0,
    double busKilometers = 0,
    double mrtKilometers = 0,
    double trainKilometers = 0,
    double hightSpeedRailKilometers = 0,
    double shortFlightKilometers = 0,
    double mediumFlightKilometers = 0,
    double longFlightKilometers = 0,
    double beefKilograms = 0,
    double porkKilograms = 0,
    double chickenKilograms = 0,
    double fishKilograms = 0,
    double riceKilograms = 0,
    double vegetablesKilograms = 0,
  }) {
    // 根據研究報告提供的排放因子計算總碳足跡
    double totalFootprint = 0;

    // 電力（2023年台灣排碳係數）
    totalFootprint += electricityKwh * 0.494;

    // 燃料
    totalFootprint += gasolineLiters * 2.234;
    totalFootprint += dieselLiters * 2.719;
    totalFootprint += naturalGasCubicMeters * 2.161;

    // 自來水
    totalFootprint += waterCubicMeters * 0.156;

    // 交通
    totalFootprint += carKilometers * 0.115;
    totalFootprint += motorcycleKilometers * 0.0951;
    totalFootprint += busKilometers * 0.04;
    totalFootprint += mrtKilometers * 0.04;
    totalFootprint += trainKilometers * 0.06;
    totalFootprint += hightSpeedRailKilometers * 0.032;
    totalFootprint += shortFlightKilometers * 0.267;
    totalFootprint += mediumFlightKilometers * 0.158;
    totalFootprint += longFlightKilometers * 0.151;

    // 食品
    totalFootprint += beefKilograms * 99.48;
    totalFootprint += porkKilograms * 12.31;
    totalFootprint += chickenKilograms * 9.87;
    totalFootprint += fishKilograms * 13.63;
    totalFootprint += riceKilograms * 4.45;
    totalFootprint += vegetablesKilograms * 1.50; // 蔬菜平均值

    return totalFootprint;
  }
}
