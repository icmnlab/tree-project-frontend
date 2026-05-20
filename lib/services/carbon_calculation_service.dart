import 'handbook_carbon_service.dart';

/// 單木碳儲量 — 依《森林碳匯調查與監測手冊》第六章（與後端 carbonCalculationService 一致）
///
///   CO₂e(kg) = V × D × BEF × (1+R) × CF × (44/12) × 1000
///   V 來自表 6-2 / 6-3 材積式，或形數 fallback
///
/// 年固碳量 [carbon_sequestration_per_year] 僅讀 DB，不在此重算。
class CarbonCalculationService {
  /// 與後端相同：DBH(cm)、樹高(m) → kg CO₂e
  static double calculateCarbonStorage(
      String species, double height, double dbh) {
    if (dbh <= 0 || height <= 0) return 0;
    return HandbookCarbonService.calculateCarbonStorage(
      species,
      height,
      dbh,
    );
  }

  @Deprecated('Read carbon_sequestration_per_year from DB instead.')
  static double calculateAnnualCarbonSequestration(
      String species, double height, double dbh, int ageYears) {
    return 0;
  }

  static int calculateTreesNeededForOffset(
      double carbonFootprint, double annualPerTree) {
    if (annualPerTree <= 0) return 0;
    return (carbonFootprint / annualPerTree).ceil();
  }

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
    double totalFootprint = 0;
    totalFootprint += electricityKwh * 0.494;
    totalFootprint += gasolineLiters * 2.234;
    totalFootprint += dieselLiters * 2.719;
    totalFootprint += naturalGasCubicMeters * 2.161;
    totalFootprint += waterCubicMeters * 0.156;
    totalFootprint += carKilometers * 0.115;
    totalFootprint += motorcycleKilometers * 0.0951;
    totalFootprint += busKilometers * 0.04;
    totalFootprint += mrtKilometers * 0.04;
    totalFootprint += trainKilometers * 0.06;
    totalFootprint += hightSpeedRailKilometers * 0.032;
    totalFootprint += shortFlightKilometers * 0.267;
    totalFootprint += mediumFlightKilometers * 0.158;
    totalFootprint += longFlightKilometers * 0.151;
    totalFootprint += beefKilograms * 99.48;
    totalFootprint += porkKilograms * 12.31;
    totalFootprint += chickenKilograms * 9.87;
    totalFootprint += fishKilograms * 13.63;
    totalFootprint += riceKilograms * 4.45;
    totalFootprint += vegetablesKilograms * 1.50;
    return totalFootprint;
  }
}
