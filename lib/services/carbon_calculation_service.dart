import 'dart:math' as Math;

class CarbonCalculationService {
  // 根據研究報告中不同樹種的碳含量比例和絕乾比重
  static final Map<String, Map<String, double>> treeParameters = {
    '相思樹': {'density': 0.65, 'carbonFraction': 0.48, 'conversionFactor': 0.312},
    '樟樹': {'density': 0.37, 'carbonFraction': 0.47, 'conversionFactor': 0.174},
    '台灣杉': {'density': 0.32, 'carbonFraction': 0.48, 'conversionFactor': 0.155},
    '欖仁': {'density': 0.52, 'carbonFraction': 0.47, 'conversionFactor': 0.244},
    '苦楝': {'density': 0.48, 'carbonFraction': 0.47, 'conversionFactor': 0.226},
    '木賊葉木麻黃': {
      'density': 0.58,
      'carbonFraction': 0.48,
      'conversionFactor': 0.278
    },
    '阿勒勃': {'density': 0.51, 'carbonFraction': 0.48, 'conversionFactor': 0.245},
    // 可根據研究報告新增更多樹種
    '其他': {'density': 0.50, 'carbonFraction': 0.48, 'conversionFactor': 0.240},
  };

  // 計算樹木碳儲存量（單位：kg CO₂e）
  static double calculateCarbonStorage(
      String species, double height, double dbh) {
    // 從參數表取得該樹種的轉換參數，若沒有則使用預設值
    final params = treeParameters[species] ?? treeParameters['其他']!;

    // 計算材積 (m³)
    // 使用台灣常用公式：立木材積 = (DBH(m))² × 0.79 × H(m) × 形數(0.45)
    final dbhInMeters = dbh / 100; // 將公分轉為公尺
    final volume = Math.pow(dbhInMeters, 2) * 0.79 * height * 0.45;

    // 轉換為生物量 (kg)
    final biomass = volume * params['density']! * 1000;

    // 擴展至全樹生物量（含地下部）
    // 根據研究使用根莖比 (R) 約 0.25
    final totalBiomass = biomass * 1.25;

    // 計算碳儲存量 (kg C)
    final carbonStock = totalBiomass * params['carbonFraction']!;

    // 轉換為 CO₂e (kg)
    final co2eStock = carbonStock * (44 / 12); // CO₂ 與 C 的分子量比

    return co2eStock;
  }

  // 計算年碳吸收量（單位：kg CO₂e/年）
  static double calculateAnnualCarbonSequestration(
      String species, double height, double dbh, int ageYears) {
    // 獲取總碳儲存量
    final totalStorage = calculateCarbonStorage(species, height, dbh);

    // 根據樹齡計算年均吸收量
    // 研究顯示幼齡至中齡林階段碳吸收速率最高
    double annualRate;
    if (ageYears <= 0) {
      // 預設情況，使用研究中的平均值
      annualRate = 5.0; // 台灣常見樹木年碳吸收率約5-10 kgCO₂/株/年
    } else if (ageYears < 5) {
      // 幼齡期（快速生長）
      annualRate = totalStorage / ageYears * 0.15;
    } else if (ageYears < 20) {
      // 中齡期（生長高峰）
      annualRate = totalStorage / ageYears * 0.10;
    } else if (ageYears < 50) {
      // 成熟期（生長減緩）
      annualRate = totalStorage / ageYears * 0.05;
    } else {
      // 老齡期（大型老樹仍持續積碳）
      annualRate = totalStorage / ageYears * 0.03;
    }

    // 針對特定樹種調整係數
    if (species == '竹子' || species.contains('竹')) {
      // 研究顯示竹子固碳量是一般樹木的2-4倍
      annualRate *= 2.5;
    }

    return annualRate;
  }

  // 計算抵換碳足跡所需樹木數量
  static int calculateTreesNeededForOffset(double carbonFootprint,
      String species, double avgHeight, double avgDbh, int avgAge) {
    final annualSequestration =
        calculateAnnualCarbonSequestration(species, avgHeight, avgDbh, avgAge);
    if (annualSequestration <= 0) return 0;

    // 計算所需樹木數量 = 碳足跡 / 單株年均吸收量
    return (carbonFootprint / annualSequestration).ceil();
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
