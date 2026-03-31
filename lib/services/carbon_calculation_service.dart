import 'dart:math' as Math;

/// Carbon storage & sequestration calculator.
///
/// Methodology — Chave et al. (2014) pantropical allometric equation:
///   Full model  : AGB = 0.0673 × (ρ × D² × H)^0.976  [kg]
///   Simplified  : AGB = exp(−2.48 + 2.4835 × ln(D))   [kg]  (DBH-only)
///   Total Biomass = 1.24 × AGB  (root-to-shoot ratio 0.24)
///   Carbon        = 0.50 × TB   (IPCC 2006 default carbon fraction)
///   CO₂e          = C × 3.67    (molecular weight ratio 44 / 12)
///
/// References:
///   [1] Chave, J. et al. (2014). Improved allometric models to estimate the
///       aboveground biomass of tropical trees. Global Change Biology, 20(10),
///       3177–3190. https://doi.org/10.1111/gcb.12629
///   [2] IPCC (2006). Guidelines for National Greenhouse Gas Inventories.
///       Vol. 4, Ch. 4, Table 4.3.
///   [3] Mokany, K. et al. (2006). Critical analysis of root:shoot ratios in
///       terrestrial biomes. Global Change Biology, 12(1), 84–96.
///   [4] Zanne, A.E. et al. (2009). Global Wood Density Database. Dryad.
class CarbonCalculationService {
  static const double _carbonFraction = 0.50; // IPCC 2006
  static const double _rootShootExpansion = 1.24; // Mokany et al. 2006
  static const double _co2ConversionFactor = 3.67; // 44/12
  static const double _defaultGrowthRate = 0.03; // 3 % yr⁻¹

  // Wood density ρ (g/cm³) — cross-referenced with Zanne et al. (2009) GWDD.
  // Values represent basic specific gravity (oven-dry mass / green volume).
  // Verified against: wood-database.com, ICRAF Agroforestry Tree Database,
  // and Taiwan Forestry Bureau published tables where available.
  // Unverified entries retain the tree_carbon_data DB average ((min+max)/2).
  static final Map<String, double> speciesWoodDensity = {
    // --- 74 species from tree_carbon_data DB (id 1–74) ---
    // Ficus spp. corrected: DB values were ~0.10 above GWDD median
    '榕樹': 0.55, '小葉欖仁': 0.58, '樟樹': 0.52, '白千層': 0.65,
    '鳳凰木': 0.50, '臺灣欒樹': 0.58, '羅漢松': 0.57, '構樹': 0.40,
    '黑板樹': 0.35, '銀合歡': 0.65, '欖仁': 0.56, '大葉桃花心木': 0.55,
    '苦楝': 0.48, '印度橡膠樹': 0.50, '赤桉': 0.70, '茄苳': 0.64,
    '楓香': 0.58, '黃槿': 0.52, '蒲葵': 0.48, '流蘇': 0.60,
    '木賊葉木麻黃': 0.83, '瓊崖海棠': 0.68, '白榕': 0.52, '雞蛋花': 0.53,
    '龍柏': 0.53, '肯氏南洋杉': 0.59, '菩提樹': 0.49, '可可椰子': 0.43,
    '白水木': 0.66, '土肉桂': 0.56, '大葉山欖': 0.72, '小葉桃花心木': 0.55,
    '海檬果': 0.52, '水黃皮': 0.70, '洋紅風鈴木': 0.59, '檄樹': 0.53,
    '毛柿': 0.68, '鐵色': 0.78, '馬拉巴栗': 0.46, '金龜樹': 0.68,
    '棋盤腳': 0.56, '破布子': 0.54, '大葉合歡': 0.63, '菲島福木': 0.72,
    '楊桃': 0.50, '芒果樹': 0.59, '緬梔': 0.52, '黃連木': 0.66,
    '潺槁樹': 0.57, '阿勒勃': 0.54, '欖仁舅': 0.62, '蘭嶼羅漢松': 0.54,
    '無葉檉柳': 0.70, '月橘': 0.78, '鴨腳木': 0.53, '鐵刀木': 0.73,
    '巴西乳香': 0.59, '西印度櫻桃': 0.70, '釋迦': 0.53, '蓮霧': 0.66,
    '白玉蘭': 0.56, '臺灣胡桃': 0.72, '龍眼': 0.69, '墨水樹': 0.54,
    '中東海棗': 0.48, '小葉南洋杉': 0.55, '人心果': 0.64, '九丁榕': 0.52,
    '雀榕': 0.52, '大花紫薇': 0.68, '大王椰子': 0.43, '雨豆樹': 0.54,
    '櫸': 0.68, '血桐': 0.48,
    // --- Additional common species not yet in DB ---
    '相思樹': 0.65, '台灣杉': 0.32, '台灣櫸': 0.68, '光蠟樹': 0.56,
    '牛樟': 0.52, '桂花': 0.72, '台灣肖楠': 0.45, '柳杉': 0.35,
  };

  // Scientific name → Chinese common name (for PlantNet integration)
  static final Map<String, String> _scientificToCommon = {
    'Ficus microcarpa': '榕樹', 'Terminalia mantaly': '小葉欖仁',
    'Cinnamomum camphora': '樟樹', 'Melaleuca leucadendra': '白千層',
    'Delonix regia': '鳳凰木', 'Koelreuteria elegans': '臺灣欒樹',
    'Podocarpus macrophyllus': '羅漢松', 'Broussonetia papyrifera': '構樹',
    'Alstonia scholaris': '黑板樹', 'Leucaena leucocephala': '銀合歡',
    'Swietenia macrophylla': '大葉桃花心木', 'Melia azedarach': '苦楝',
    'Ficus elastica': '印度橡膠樹', 'Eucalyptus camaldulensis': '赤桉',
    'Bischofia javanica': '茄苳', 'Liquidambar formosana': '楓香',
    'Hibiscus tiliaceus': '黃槿', 'Livistona chinensis': '蒲葵',
    'Casuarina equisetifolia': '木賊葉木麻黃', 'Calophyllum inophyllum': '瓊崖海棠',
    'Ficus religiosa': '菩提樹', 'Cocos nucifera': '可可椰子',
    'Cinnamomum osmophloeum': '土肉桂', 'Murraya paniculata': '月橘',
    'Cassia siamea': '鐵刀木', 'Roystonea regia': '大王椰子',
    'Samanea saman': '雨豆樹', 'Zelkova serrata': '櫸',
    'Macaranga tanarius': '血桐', 'Mangifera indica': '芒果樹',
    'Dimocarpus longan': '龍眼', 'Syzygium samarangense': '蓮霧',
    'Pachira macrocarpa': '馬拉巴栗', 'Lagerstroemia speciosa': '大花紫薇',
    'Acacia confusa': '相思樹', 'Taiwania cryptomerioides': '台灣杉',
    'Araucaria cunninghamii': '肯氏南洋杉', 'Ficus benjamina': '九丁榕',
    'Ficus superba': '雀榕', 'Annona squamosa': '釋迦',
    'Schefflera octophylla': '鴨腳木', 'Plumeria rubra': '雞蛋花',
  };

  static const double _defaultWoodDensity = 0.58; // tropical mean (Chave 2014)

  /// Look up wood density by species name (Chinese or scientific).
  static double getWoodDensity(String species) {
    // Direct Chinese name lookup
    if (speciesWoodDensity.containsKey(species)) {
      return speciesWoodDensity[species]!;
    }
    // Scientific name lookup
    final common = _scientificToCommon[species];
    if (common != null && speciesWoodDensity.containsKey(common)) {
      return speciesWoodDensity[common]!;
    }
    // Partial match (e.g., "台灣欒樹" vs "臺灣欒樹")
    for (final key in speciesWoodDensity.keys) {
      if (key.contains(species) || species.contains(key)) {
        return speciesWoodDensity[key]!;
      }
    }
    return _defaultWoodDensity;
  }

  // 計算樹木碳儲存量（單位：kg CO₂e）
  // Chave et al. (2014) — uses full model when height available
  static double calculateCarbonStorage(
      String species, double height, double dbh) {
    if (dbh <= 0) return 0;

    final density = getWoodDensity(species);

    double agb;
    if (height > 0 && density > 0) {
      // Full Chave 2014: AGB = 0.0673 × (ρ × D² × H)^0.976
      agb = 0.0673 * Math.pow(density * dbh * dbh * height, 0.976);
    } else {
      // Simplified: AGB = exp(−2.48 + 2.4835 × ln(D))
      agb = Math.exp(-2.48 + 2.4835 * Math.log(dbh));
    }

    final totalBiomass = _rootShootExpansion * agb;
    final carbonStock = _carbonFraction * totalBiomass;
    return carbonStock * _co2ConversionFactor;
  }

  // 計算年碳吸收量（單位：kg CO₂e/年）
  // Mean annual increment = total storage / age, or default 3 % yr⁻¹
  static double calculateAnnualCarbonSequestration(
      String species, double height, double dbh, int ageYears) {
    final totalStorage = calculateCarbonStorage(species, height, dbh);
    if (totalStorage <= 0) return 0;

    if (ageYears > 0) {
      return totalStorage / ageYears;
    }
    return totalStorage * _defaultGrowthRate;
  }

  // 計算抵換碳足跡所需樹木數量
  static int calculateTreesNeededForOffset(double carbonFootprint,
      String species, double avgHeight, double avgDbh, int avgAge) {
    final annualSequestration =
        calculateAnnualCarbonSequestration(species, avgHeight, avgDbh, avgAge);
    if (annualSequestration <= 0) return 0;
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
