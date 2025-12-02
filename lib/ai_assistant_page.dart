import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:logger/logger.dart';

import 'constants/colors.dart';
import 'widgets/loading_indicator.dart';
import 'widgets/error_dialog.dart';
import 'services/ai_service.dart';
import 'services/api_service.dart';
import 'services/statistics_service.dart';
import 'services/carbon_service.dart';
import 'services/management_service.dart';
import 'services/species_service.dart';
import 'services/carbon_data_service.dart';
import 'config/app_config.dart';

// 聊天消息模型
class ChatMessage {
  final String role;
  final String content;
  final bool isUser;
  final bool showCarbonChart;
  final List<Map<String, dynamic>>? sources;

  ChatMessage({
    required this.role,
    required this.content,
    required this.isUser,
    this.showCarbonChart = false,
    this.sources,
  });
}

// 現代化消息氣泡組件 v2.0
class _MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AI 頭像（左側）
          if (!isUser) _buildAvatar(isUser),
          if (!isUser) const SizedBox(width: 12),
          
          // 訊息氣泡
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: isUser
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.portBlue.withOpacity(0.15),
                          AppColors.portBlue.withOpacity(0.08),
                        ],
                      )
                    : null,
                color: isUser ? null : AppColors.surfaceLight,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isUser ? 20 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 20),
                ),
                border: Border.all(
                  color: isUser 
                      ? AppColors.portBlue.withOpacity(0.2)
                      : AppColors.neutral200,
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: isUser
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  MarkdownBody(
                    data: message.content,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet(
                      p: TextStyle(
                        color: isUser ? AppColors.neutral800 : AppColors.neutral900,
                        fontSize: 15,
                        height: 1.5,
                      ),
                      h1: TextStyle(
                        color: AppColors.neutral900,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                      h2: TextStyle(
                        color: AppColors.neutral900,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      code: TextStyle(
                        backgroundColor: AppColors.neutral100,
                        color: AppColors.forestGreen,
                        fontSize: 13,
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: AppColors.neutral100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      blockquoteDecoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: AppColors.forestGreen,
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                    onTapLink: (text, href, title) {
                      if (href != null) {
                        launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
                      }
                    },
                  ),
                  if (!isUser &&
                      message.sources != null &&
                      message.sources!.isNotEmpty)
                    _buildSourcesExpansionTile(context, message.sources!),
                ],
              ),
            ),
          ),
          
          // 用戶頭像（右側）
          if (isUser) const SizedBox(width: 12),
          if (isUser) _buildAvatar(isUser),
        ],
      ),
    );
  }

  Widget _buildAvatar(bool isUser) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isUser
              ? [AppColors.portBlue, AppColors.primaryLight]
              : [AppColors.forestGreen, AppColors.accentLight],
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: (isUser ? AppColors.portBlue : AppColors.forestGreen).withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(
        isUser ? Icons.person_rounded : Icons.eco_rounded,
        size: 20,
        color: Colors.white,
      ),
    );
  }

  Widget _buildSourcesExpansionTile(
    BuildContext context,
    List<Map<String, dynamic>> sources,
  ) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: false, // 預設不展開
        tilePadding: EdgeInsets.zero,
        title: Text(
          '查看 ${sources.length} 個資料來源', // 更新標題
          style: TextStyle(
            fontSize: 12,
            color: AppColors.forestGreen,
            fontWeight: FontWeight.normal,
          ),
        ),
        children: sources.map((source) {
          // Safely access fields from the source map
          final knowledgeId =
              source['id']; // This is tree_knowledge_embeddings_v2.id
          final score = source['score'] as num?;

          // Fields from the new structure
          final textContent = source['text_content'] as String?;
          final summaryCn = source['summary_cn'] as String?;
          final sourceType = source['source_type'] as String?;
          final internalSourceTableName =
              source['internal_source_table_name'] as String?;
          final internalSourceRecordId = source['internal_source_record_id']
              ?.toString(); // Original source_id functionality
          final originalSourceTitle =
              source['original_source_title'] as String?;
          final originalSourceAuthor =
              source['original_source_author'] as String?;
          final originalSourcePublicationYear =
              source['original_source_publication_year'] as int?;
          final originalSourceUrlOrDoi =
              source['original_source_url_or_doi'] as String?;
          final originalSourceTypeDetailed =
              source['original_source_type_detailed'] as String?;
          final keywords = source['keywords'] as String?;
          final confidenceScore = source['confidence_score'] as int?;
          // final lastVerifiedAt = source['last_verified_at'] as String?; // Not displayed for now

          List<Widget> details = [];

          details.add(
            Text(
              '知識庫 ID: $knowledgeId',
              style: const TextStyle(
                fontSize: 10,
                color: Colors.grey,
                fontWeight: FontWeight.normal,
              ), // 調整樣式
            ),
          );

          if (originalSourceTitle != null && originalSourceTitle.isNotEmpty) {
            details.add(
              Text(
                '標題: $originalSourceTitle',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ); // 加粗標題
          }
          if (originalSourceAuthor != null && originalSourceAuthor.isNotEmpty) {
            details.add(
              Text(
                '作者/機構: $originalSourceAuthor',
                style: const TextStyle(fontSize: 10),
              ),
            );
          }
          if (originalSourceTypeDetailed != null &&
              originalSourceTypeDetailed.isNotEmpty) {
            details.add(
              Text(
                '來源類型: $originalSourceTypeDetailed',
                style: const TextStyle(fontSize: 10),
              ),
            );
          } else if (sourceType != null && sourceType.isNotEmpty) {
            details.add(
              Text('來源類型: $sourceType', style: const TextStyle(fontSize: 10)),
            );
          }

          if (internalSourceTableName != null &&
              internalSourceRecordId != null) {
            details.add(
              Text(
                '內部來源: $internalSourceTableName (ID: $internalSourceRecordId)',
                style: const TextStyle(fontSize: 9, color: Colors.grey),
              ),
            ); // 調整樣式
          }

          if (originalSourcePublicationYear != null) {
            details.add(
              Text(
                '發表年份: $originalSourcePublicationYear',
                style: const TextStyle(fontSize: 10),
              ),
            );
          }

          if (score != null) {
            details.add(
              Text(
                '相關度: ${score.toStringAsFixed(3)}',
                style: const TextStyle(fontSize: 10, color: Colors.blueGrey),
              ),
            );
          }
          if (confidenceScore != null) {
            details.add(
              Text(
                '可信度評分: $confidenceScore/5',
                style: const TextStyle(fontSize: 10, color: Colors.orange),
              ),
            );
          }

          if (summaryCn != null && summaryCn.isNotEmpty) {
            details.add(
              Padding(
                padding: const EdgeInsets.only(top: 3.0, bottom: 3.0),
                child: Text(
                  '摘要: $summaryCn',
                  style: const TextStyle(
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
          }

          // Option to view full text_content (if different from summary_cn and not too long)
          if (textContent != null &&
              textContent.isNotEmpty &&
              textContent != summaryCn) {
            details.add(
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text(
                  "查看原始文本片段",
                  style: TextStyle(fontSize: 10, color: Colors.teal),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      textContent,
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ],
              ),
            );
          }

          if (keywords != null && keywords.isNotEmpty) {
            details.add(
              Text(
                '關鍵字: $keywords',
                style: const TextStyle(fontSize: 9, color: Colors.grey),
              ),
            );
          }

          if (originalSourceUrlOrDoi != null &&
              originalSourceUrlOrDoi.isNotEmpty) {
            final Uri? uri = Uri.tryParse(originalSourceUrlOrDoi);
            bool canLaunch =
                uri != null && (uri.isScheme('http') || uri.isScheme('https'));
            details.add(
              Padding(
                padding: const EdgeInsets.only(top: 3.0),
                child: InkWell(
                  onTap: canLaunch
                      ? () async {
                          // if (await canLaunchUrl(uri)) { // canLaunchUrl is from url_launcher < 6.1
                          //   await launchUrl(uri); // launchUrl is from url_launcher < 6.1
                          // } else {
                          //   ScaffoldMessenger.of(context).showSnackBar(
                          //     SnackBar(content: Text('無法開啟連結: $originalSourceUrlOrDoi')),
                          //   );
                          // }
                          // For url_launcher ^6.1.0 and later:
                          try {
                            await launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('無法開啟連結: $e')),
                            );
                          }
                        }
                      : null,
                  child: Text(
                    '來源連結: $originalSourceUrlOrDoi',
                    style: TextStyle(
                      fontSize: 10,
                      color: canLaunch ? Colors.blue : Colors.grey,
                      decoration: canLaunch
                          ? TextDecoration.underline
                          : TextDecoration.none,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            );
          }

          return ListTile(
            dense: true,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: details,
            ),
            // No separate subtitle, all info is in details list
          );
        }).toList(),
      ),
    );
  }
}

class AIAssistantPage extends StatefulWidget {
  final String userId;
  final List<String> selectedProjectAreas;

  const AIAssistantPage({
    Key? key,
    required this.userId,
    required this.selectedProjectAreas,
  }) : super(key: key);

  @override
  _AIAssistantPageState createState() => _AIAssistantPageState();
}

class _AIAssistantPageState extends State<AIAssistantPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  String _errorMessage = '';
  final bool _isShowingReport = false;
  Map<String, dynamic>? _reportData;
  Map<String, dynamic>? _speciesRecommendations;
  Map<String, dynamic>? _managementAdvice;

  // Services
  final AiService _aiService = AiService();
  final StatisticsService _statisticsService = StatisticsService();
  final CarbonService _carbonService = CarbonService();
  final ManagementService _managementService = ManagementService();
  final CarbonDataService _carbonDataService = CarbonDataService();
  final TreeSpeciesService _speciesService = TreeSpeciesService();

  // 專案區位選擇
  List<String> _selectedProjectAreas = [];
  List<String> _projectAreas = ['A1區', 'B2區', 'C3區', 'D4區'];
  bool _isLoadingAreas = false;

  // 新增標籤控制器，用於在聊天、報告和碳足跡視圖間切換
  late TabController _tabController;
  int _currentTabIndex = 0;
  String _selectedModel = 'gemini-2.5-flash'; // 預設模型
  bool _showKnowledgeSource = true; // 新增：是否顯示知識庫來源的開關

  // Define model lists
  final Map<String, String> _prodModels = {
    'DeepSeek-V3': 'deepseek-ai/DeepSeek-V3',
    'Qwen3-VL-32B-Instruct': 'Qwen/Qwen3-VL-32B-Instruct',
  };

  final Map<String, String> _allModels = {
    'GPT-5': 'gpt-5',
    'Gemini 2.5 Flash': 'gemini-2.5-flash',
    'Claude Haiku 4.5': 'claude-haiku-4-5',
    'DeepSeek-V3': 'deepseek-ai/DeepSeek-V3',
    'Qwen3-VL-32B-Instruct': 'Qwen/Qwen3-VL-32B-Instruct',
  };

  late Map<String, String> _availableModels;

  // 碳吸收預測數據
  List<FlSpot> _carbonProjectionData = [];

  // === Carbon Footprint Calculator State Variables ===
  final _carbonFootprintFormKey = GlobalKey<FormState>();
  String? _selectedActivityType;
  final TextEditingController _activityAmountController =
      TextEditingController();
  String? _selectedActivityUnit;
  Map<String, dynamic>? _carbonFootprintResult;
  bool _isCalculatingFootprint = false;
  String? _footprintCalculationError;

  late Map<String, List<String>> _activityUnits;
  late List<String> _activityTypes;
  // === END Carbon Footprint Calculator State Variables ===

  // === Species Comparison State Variables ===
  List<Map<String, dynamic>> _availableSpeciesForComparison = [];
  List<dynamic> _selectedSpeciesObjectsForComparison =
      []; // Stores the full species objects
  final List<Map<String, String>> _availableRegionsForComparison = [
    {'code': 'NORTH', 'name': '北部'},
    {'code': 'CENTRAL', 'name': '中部'},
    {'code': 'SOUTH', 'name': '南部'},
    {'code': 'EAST', 'name': '東部'},
    {'code': 'COASTAL', 'name': '沿海'},
    {'code': 'MOUNTAIN', 'name': '山區'},
    {'code': 'URBAN', 'name': '都市'},
  ];
  String? _selectedRegionCodeForComparison;
  List<Map<String, dynamic>>? _comparisonData;
  bool _isFetchingSpeciesList = false;
  bool _isFetchingComparisonData = false;
  String? _speciesComparisonError;
  final GlobalKey<FormState> _speciesComparisonFormKey = GlobalKey<FormState>();
  // === END Species Comparison State Variables ===

  // === Management Actions State Variables ===
  List<Map<String, dynamic>> _managementActions = [];
  bool _isLoadingManagementActions = false;
  String? _managementActionsError;
  Map<String, dynamic?> _managementActionFilters = {
    'area_name': null,
    'is_done': null, // null for all, true for done, false for not done
    'category': null,
  };
  int _managementActionsTotal = 0;
  int _managementActionsOffset = 0;
  final int _managementActionsLimit = 15;
  List<String> _projectAreasForFiltering =
      []; // Will be populated from _projectAreas
  final List<String> _actionCategories = ['健康維護', '碳吸存優化', '長期規劃'];
  // === END Management Actions State Variables ===

  @override
  void initState() {
    super.initState();
    _determineAvailableModels();
    _initializeActivityTypesAndUnits();
    _addSystemMessage();
    _loadProjectAreas().then((_) {
      // Ensure _projectAreas is loaded before initializing filters
      if (mounted) {
        setState(() {
          _projectAreasForFiltering = List.from(
            _projectAreas,
          ); // Initialize here
        });
      }
    });
    _fetchAvailableSpeciesForComparison();
    _fetchManagementActions(); // Fetch initial management actions

    // 初始化標籤控制器
    _tabController = TabController(length: 4, vsync: this); // Changed to 4 tabs
    _tabController.addListener(() {
      if (mounted) {
        setState(() {
          _currentTabIndex = _tabController.index;
        });
      }
    });
  }

  void _initializeActivityTypesAndUnits() {
    // Data parsed from emission_factors.sql
    _activityUnits = {
      '電力': ['kWh'],
      '台灣自來水': ['m3'],
      '臺北自來水': ['m3'],
      '燃料油(蒸餘油/重油)固定源': ['L'],
      '柴油固定源': ['L'],
      '汽油固定源': ['L'],
      '天然氣固定源': ['m3'],
      '液化石油氣固定源': ['L'],
      '煤油固定源': ['L'],
      '柴油公路運輸': ['L'],
      '柴油鐵路非道路運輸': ['L'],
      '柴油水路運輸': ['L'],
      '柴油捕撈移動源': ['L'],
      '自用大客車(柴油)': ['pkm'],
      '營業大客車(市區公車及公路客運-柴油)': ['pkm'],
      '營業遊覽車(柴油)': ['pkm'],
      '自用大貨車(柴油)': ['tkm'],
      '自用小貨車(柴油)': ['tkm'],
      '營業小貨車(柴油)': ['tkm'],
      '營業大貨車(柴油)': ['tkm'],
      '汽油移動源': ['L'],
      '自用小客車(汽油)': ['pkm'],
      '營業小客車(汽油)': ['pkm'],
      '機器腳踏車(汽油)': ['pkm'],
      '自用小貨車(汽油)': ['tkm'],
      '營業小貨車(汽油)': ['tkm'],
      '高速鐵路運輸服務': ['pkm'],
      '臺灣鐵路運輸服務(柴聯車)': ['pkm'],
      '臺灣鐵路運輸服務(電聯車)': ['pkm'],
      '聚丙烯(PP)': ['kg'],
      '低密度聚乙烯(LDPE)': ['kg'],
      '高密度聚乙烯(HDPE)': ['kg'],
      '聚氯乙烯(PVC)': ['kg'],
      '聚對苯二甲酸乙二酯(PET)': ['kg'],
      '生鐵': ['kg'],
      '鋼板': ['kg'],
      '鋁錠': ['kg'],
      '再生鋁錠': ['kg'],
      '牛皮紙': ['kg'],
      '瓦楞芯紙': ['kg'],
      '原生木漿影印紙': ['kg'],
      '再生影印紙': ['kg'],
      '水泥熟料': ['kg'],
      '玻璃容器': ['kg'],
      '航空貨物運輸服務': ['tkm'],
      '國內海運貨物運輸服務(柴油動力)': ['tkm'],
      '國際海運貨物運輸服務(燃料油動力)': ['tkm'],
      '航空旅客運輸服務(松山-金門)': ['pkm'],
      '不鏽鋼鋼胚': ['kg'],
      '不鏽鋼冷軋鋼捲': ['kg'],
      '金': ['kg'],
      '鉑': ['kg'],
      '純銅線': ['kg'],
      '鋅錠': ['kg'],
      '再生鋅錠': ['kg'],
      '乙二醇': ['kg'],
      '異丙醇': ['kg'],
      '甲醛，37％': ['kg'],
      '環氧樹脂': ['kg'],
      '氨': ['kg'],
      '鹽酸，37％': ['kg'],
      '硫酸，98％': ['kg'],
      '氫氧化鈉，45％': ['kg'],
      '甲醇': ['kg'],
      '水泥(不分型號)': ['kg'],
      '預拌混凝土(210kgf/cm2)': ['m3'],
      '預拌混凝土(280kgf/cm2)': ['m3'],
      '鋼筋': ['kg'],
      '平板玻璃': ['kg'],
      '瓦楞紙板(AB楞)': ['kg'],
      '食品包裝紙容器': ['kg'],
      '廢棄物焚化清理服務(南部科學工業園區-台南園區)': ['t'],
      '廢棄物掩埋清理服務(南部科學工業園區-台南園區)': ['t'],
      '有害事業廢棄物固化處理服務': ['t'],
      '食用大豆油': ['kg'],
      '鮮乳': ['kg'],
      '瓶裝水（600ml，PET包裝）': ['瓶'],
      'OPP膠帶(0.043mm*48mm*80M)': ['卷'],
    };
    _activityTypes = _activityUnits.keys.toList();
  }

  void _determineAvailableModels() {
    final currentEnv = AppConfig().environment;
    if (currentEnv == Environment.prod) {
      _availableModels = _prodModels;
      // Ensure the default model is valid for prod
      if (!_availableModels.containsValue(_selectedModel)) {
        _selectedModel = 'deepseek-ai/DeepSeek-V3'; // Set to a valid prod model
      }
    } else {
      _availableModels = _allModels;
    }
  }

  // 載入專案區位
  Future<void> _loadProjectAreas() async {
    setState(() {
      _isLoadingAreas = true;
    });

    try {
      // Refactored to use StatisticsService
      final data = await _statisticsService.getTreeStatistics();
      if (data['success'] == true && data['data']['areas'] != null) {
        final areas = data['data']['areas'] as List;
        setState(() {
          _projectAreas = areas.map((area) => area['專案區位'].toString()).toList();
          _isLoadingAreas = false;
        });
      } else {
        throw Exception('Failed to parse project areas');
      }
      /*
      final response = await http.get(
        Uri.parse('http://172.20.10.4:3000/api/tree_statistics'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['data']['areas'] != null) {
          final areas = data['data']['areas'] as List;
          setState(() {
            _projectAreas =
                areas.map((area) => area['專案區位'].toString()).toList();
            _isLoadingAreas = false;
          });
        }
      } else {
        setState(() {
          _isLoadingAreas = false;
        });
        // 添加錯誤提示
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ErrorDialog.showSnackBar(context, '無法載入專案區位列表');
          });
        }
      }
      */
    } catch (e) {
      setState(() {
        _isLoadingAreas = false;
      });
      // 添加錯誤提示
      print('載入專案區位時出錯: $e');
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ErrorDialog.showSnackBar(context, '載入專案區位失敗，請檢查網路連線');
        });
      }
    }
  }

  void _addSystemMessage() {
    _messages.add(
      ChatMessage(
        role: 'assistant',
        content: '您好！我是您的永續發展與碳匯助手，有什麼我可以幫您的嗎？您可以：\n\n'
            '1. 詢問關於樹木永續管理的問題\n'
            '2. 了解樹木的碳吸存潛力和環境效益\n'
            '3. 獲取樹種優化和管理建議以提高碳吸存\n'
            '4. 點擊下方標籤頁查看AI永續分析報告和碳足跡計算',
        isUser: false,
      ),
    );
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final userMessage = _messageController.text;
    _messageController.clear();

    setState(() {
      _messages.add(
        ChatMessage(role: 'user', content: userMessage, isUser: true),
      );
      _isLoading = true;
    });

    _scrollToBottom();

    try {
      await _getAIResponse(userMessage);
    } catch (e) {
      setState(() {
        _messages.add(
          ChatMessage(
            role: 'assistant',
            content: '抱歉，發生錯誤：$e\n請確認後端服務器是否正常運作。',
            isUser: false,
          ),
        );
      });
      // 添加 SnackBar 提示
      if (mounted) {
        ErrorDialog.showSnackBar(context, '訊息發送失敗，請檢查網路連線');
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  Future<void> _getAIResponse(String message) async {
    try {
      setState(() {
        _isLoading = true;
      });

      // Refactored to use AiService
      final response = await _aiService.getChatResponse(
        message,
        _selectedProjectAreas,
        _selectedModel,
        widget.userId,
      );

      if (response['success'] == true) {
        final aiResponse = response['response'] ?? '對不起，我現在無法回應您的問題。';
        final List<dynamic>? sourcesData = response['sources'];
        final List<Map<String, dynamic>>? sources =
            sourcesData?.map((s) => s as Map<String, dynamic>).toList();
        final String modelUsed = response['modelUsed'] ?? _selectedModel;
        setState(() {
          _messages.add(
            ChatMessage(
              role: 'assistant',
              content: '$aiResponse\n\n*(由 ${modelUsed.split('/').last} 回答)*',
              isUser: false,
              sources: sources,
            ),
          );
        });
      } else {
        // API 請求失敗，嘗試使用 OpenAI 直接回應
        await _useOpenAIDirectly(message);
      }
      /*
      // 移除重複添加使用者訊息的程式碼
      final response = await http.post(
        Uri.parse('http://172.20.10.4:3000/api/chat'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'message': message,
          'userId': widget.userId,
          'projectAreas': _selectedProjectAreas,
          'model_preference': _selectedModel,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final aiResponse = data['response'] ?? '對不起，我現在無法回應您的問題。';
        final List<dynamic>? sourcesData = data['sources'];
        final List<Map<String, dynamic>>? sources =
            sourcesData?.map((s) => s as Map<String, dynamic>).toList();
        final String modelUsed = data['modelUsed'] ?? _selectedModel;

        setState(() {
          _messages.add(ChatMessage(
            role: 'assistant',
            content: '$aiResponse\n\n*(由 ${modelUsed.split('/').last} 回答)*',
            isUser: false,
            sources: sources,
          ));
        });
      } else {
        // API 請求失敗，嘗試使用 OpenAI 直接回應
        await _useOpenAIDirectly(message);
      }
      */
    } catch (e) {
      print('獲取AI回應時出錯: $e');
      // 出錯時也嘗試直接使用 OpenAI
      await _useOpenAIDirectly(message);
    } finally {
      setState(() {
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  // 檢查是否為簡單問候語
  bool _isGreeting(String message) {
    final lowerMessage = message.toLowerCase().trim();
    return lowerMessage == '你好' ||
        lowerMessage == 'hello' ||
        lowerMessage == 'hi' ||
        lowerMessage == '嗨' ||
        lowerMessage == '哈囉' ||
        lowerMessage == '您好' ||
        lowerMessage == '早安' ||
        lowerMessage == '午安' ||
        lowerMessage == '晚安';
  }

  // 直接使用 OpenAI API
  Future<void> _useOpenAIDirectly(String message) async {
    try {
      // This entire block should be moved to the backend for security reasons.
      // The frontend should call a new endpoint like '/api/ai/direct-chat'
      // which then calls the OpenAI API with the key stored securely on the server.
      // For now, commenting out as requested.
      // Refactored to call the new backend endpoint
      final treeData = await _fetchTreeData();
      final systemPrompt =
          '你是一位樹木與永續碳匯專家，具有林業、生態學和碳匯計算專業知識。以下是用戶的樹木數據: $treeData';

      final response = await _aiService.getDirectOpenAIChat(
        message,
        systemPrompt,
      );

      if (response['success'] == true) {
        final aiResponse = response['response'];
        setState(() {
          _messages.add(
            ChatMessage(role: 'assistant', content: aiResponse, isUser: false),
          );
        });
      } else {
        throw Exception(response['message'] ?? '備用AI服務請求失敗');
      }
      /*
      // Legacy direct OpenAI call removed for security
      */
      /*
       setState(() {
        _messages.add(ChatMessage(
          role: 'assistant',
          content: '抱歉，備用AI服務目前無法使用。請檢查您的網路連接或稍後再試。',
          isUser: false,
        ));
      });
      */
    } catch (e) {
      print('使用OpenAI時出錯: $e');
      setState(() {
        _messages.add(
          ChatMessage(
            role: 'assistant',
            content: '抱歉，備用AI服務目前無法使用。請檢查您的網路連接或稍後再試。',
            isUser: false,
          ),
        );
      });
      // 添加 SnackBar 提示
      if (mounted) {
        ErrorDialog.showSnackBar(context, 'AI 回應發生錯誤');
      }
    }
  }

  // 獲取樹木數據作為上下文
  Future<String> _fetchTreeData() async {
    try {
      // 檢查是否有選擇項目區域
      if (_selectedProjectAreas.isEmpty) {
        return '沒有可用的樹木數據';
      }

      // This endpoint doesn't seem to exist. Assuming a generic one for now.
      // Refactored to use a hypothetical ApiService method.
      final response = await ApiService.get(
        'project_areas/${_selectedProjectAreas.first}/trees_summary',
      );

      if (response['success'] == true && response['data'] != null) {
        final treeData = response['data'];
        // 將樹木數據格式化為文本以用作上下文
        String context = '樹木數據摘要:\n';
        context += '總樹木數: ${treeData['total_trees'] ?? 0}\n';
        context += '平均樹齡: ${treeData['average_age'] ?? 0} 年\n';
        context += '主要樹種: ${treeData['primary_species']?.join(', ') ?? '未知'}\n';
        context += '總碳吸存: ${treeData['total_carbon_storage'] ?? 0} 噸\n';
        context += '年增長率: ${treeData['annual_growth_rate'] ?? 0} %\n';

        return context;
      }
      /*
      final response = await http.get(
        Uri.parse(
            'http://172.20.10.4:3000/api/project_areas/${_selectedProjectAreas.first}/trees_summary'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final treeData = data['data'];

          // 將樹木數據格式化為文本以用作上下文
          String context = '樹木數據摘要:\n';
          context += '總樹木數: ${treeData['total_trees'] ?? 0}\n';
          context += '平均樹齡: ${treeData['average_age'] ?? 0} 年\n';
          context +=
              '主要樹種: ${treeData['primary_species']?.join(', ') ?? '未知'}\n';
          context += '總碳吸存: ${treeData['total_carbon_storage'] ?? 0} 噸\n';
          context += '年增長率: ${treeData['annual_growth_rate'] ?? 0} %\n';

          return context;
        }
      }
      */
      return '無法獲取樹木數據';
    } catch (e) {
      print('獲取樹木數據時出錯: $e');
      return '無法獲取樹木數據';
    }
  }

  // 獲取永續分析報告
  Future<void> _fetchSustainabilityReport() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // Refactored to use ApiService (assuming a generic 'reports' service isn't defined yet)
      final response = await ApiService.get('sustainability_report');

      if (response['success'] == true) {
        setState(() {
          _reportData = response;
        });
      } else {
        setState(() {
          _errorMessage = '無法獲取永續分析報告：${response['message'] ?? '未知錯誤'}';
        });
        if (mounted) {
          ErrorDialog.showSnackBar(context, '無法獲取永續分析報告');
        }
      }
      /*
      final response = await http.get(
        Uri.parse('http://172.20.10.4:3000/api/sustainability_report'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _reportData = data;
        });
      } else {
        setState(() {
          _errorMessage = '無法獲取永續分析報告：${response.statusCode}';
        });
        // 添加 SnackBar 提示
        if (mounted) {
          ErrorDialog.showSnackBar(context, '無法獲取永續分析報告');
        }
      }
      */
    } catch (e) {
      setState(() {
        _errorMessage = '獲取永續分析報告時發生錯誤：$e';
      });
      // 添加 SnackBar 提示
      if (mounted) {
        ErrorDialog.showSnackBar(context, '獲取永續分析報告失敗');
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 計算碳信用
  Future<void> _calculateCarbonCredits() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // 檢查是否有選擇項目區域
      if (_selectedProjectAreas.isEmpty) {
        setState(() {
          _messages.add(
            ChatMessage(
              role: 'assistant',
              content: '請先選擇一個項目區域以計算碳信用。',
              isUser: false,
            ),
          );
          _isLoading = false;
        });
        _scrollToBottom();
        return;
      }

      try {
        // Refactored to use a hypothetical method in CarbonService
        final response = await _carbonService.getCarbonCreditsForArea(
          _selectedProjectAreas.first,
        );

        if (response['success'] == true && response['data'] != null) {
          final carbonData = response['data'];

          // 安全地提取數據，檢查是否存在必要數據
          if (carbonData == null ||
              carbonData['total_carbon_storage'] == null) {
            throw '獲取的碳信用數據不完整或格式錯誤';
          }

          // 安全地提取數據，防止undefined屬性錯誤
          final totalCarbonStorage = carbonData['total_carbon_storage'] ?? 0.0;
          final annualSequestration = carbonData['annual_sequestration'] ?? 0.0;
          final potentialCredits = carbonData['potential_credits'] ?? 0.0;
          final estimatedValue = carbonData['estimated_value'] ?? 0.0;
          final currency = carbonData['currency'] ?? 'TWD';
          final bySpecies = carbonData['by_species'] ?? [];
          final projections = carbonData['projections'] ?? [];

          // 構建響應消息
          String message = '''
**碳信用計算結果**

**總計**
- 總碳儲存量: ${totalCarbonStorage.toStringAsFixed(2)} 噸CO₂
- 年碳吸收量: ${annualSequestration.toStringAsFixed(2)} 噸CO₂/年
- 潛在碳信用: ${potentialCredits.toStringAsFixed(2)} 信用額
- 估計價值: ${estimatedValue.toStringAsFixed(2)} $currency

''';

          // 按樹種分類數據
          if (bySpecies is List && bySpecies.isNotEmpty) {
            message += '**各樹種貢獻**\n';
            for (int i = 0; i < bySpecies.length; i++) {
              if (bySpecies[i] is Map) {
                final species = bySpecies[i]['species'] ?? '未知樹種';
                final count = bySpecies[i]['count'] ?? 0;
                final storage = bySpecies[i]['carbon_storage'] ?? 0.0;
                final percentage = bySpecies[i]['percentage'] ?? 0.0;

                message +=
                    '- $species ($count棵): ${storage.toStringAsFixed(2)} 噸CO₂ (${percentage.toStringAsFixed(1)}%)\n';
              }
            }
            message += '\n';
          }

          // 未來預測
          if (projections is List && projections.isNotEmpty) {
            message += '**未來5年預測**\n';
            List<FlSpot> chartData = [];

            for (int i = 0; i < projections.length; i++) {
              if (projections[i] is Map) {
                final year = projections[i]['year'] ?? i;
                final value = projections[i]['value'] ?? 0.0;

                message +=
                    '${DateTime.now().year + year}: ${value.toStringAsFixed(2)} 噸CO₂\n';
                chartData.add(FlSpot(year.toDouble(), value.toDouble()));
              }
            }

            // 保存圖表數據以便在UI中顯示
            _carbonProjectionData = chartData;
          }

          setState(() {
            _messages.add(
              ChatMessage(
                role: 'assistant',
                content: message,
                isUser: false,
                showCarbonChart: true,
              ),
            );
          });
        } else {
          throw response['error'] ?? '獲取碳信用數據失敗';
        }
      } catch (apiError) {
        print('計算碳信用API錯誤: $apiError');

        // 使用預設碳信用數據
        final defaultMessage = '''
**碳信用計算結果**

**總計**
- 總碳儲存量: 218.45 噸CO₂
- 年碳吸收量: 12.75 噸CO₂/年
- 潛在碳信用: 215.00 信用額
- 估計價值: 64,500.00 TWD

**各樹種貢獻**
- 台灣欒樹 (12棵): 56.40 噸CO₂ (25.8%)
- 樟樹 (8棵): 72.80 噸CO₂ (33.3%)
- 楓香 (10棵): 45.25 噸CO₂ (20.7%)
- 相思樹 (5棵): 28.50 噸CO₂ (13.0%)
- 其他樹種 (4棵): 15.50 噸CO₂ (7.2%)

**未來5年預測**
${DateTime.now().year}: 218.45 噸CO₂
${DateTime.now().year + 1}: 231.20 噸CO₂
${DateTime.now().year + 2}: 244.35 噸CO₂
${DateTime.now().year + 3}: 257.90 噸CO₂
${DateTime.now().year + 4}: 271.85 噸CO₂
${DateTime.now().year + 5}: 286.20 噸CO₂

*備註: 此為估算值，實際碳匯量會因各種因素而變動。*
''';

        // 創建示例圖表數據
        final currentYear = DateTime.now().year;
        final List<FlSpot> exampleChartData = [
          const FlSpot(0, 218.45),
          const FlSpot(1, 231.20),
          const FlSpot(2, 244.35),
          const FlSpot(3, 257.90),
          const FlSpot(4, 271.85),
          const FlSpot(5, 286.20),
        ];

        // 保存圖表數據
        _carbonProjectionData = exampleChartData;

        setState(() {
          _messages.add(
            ChatMessage(
              role: 'assistant',
              content: defaultMessage,
              isUser: false,
              showCarbonChart: true,
            ),
          );
        });
      }
    } catch (e) {
      print('計算碳信用時發生嚴重錯誤：$e');
      setState(() {
        _messages.add(
          ChatMessage(
            role: 'assistant',
            content: '抱歉，計算碳信用時發生錯誤。請稍後再試。',
            isUser: false,
          ),
        );
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  // 獲取樹種推薦
  Future<void> _fetchSpeciesRecommendations() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // 獲取已選擇的區域資料
      final selectedAreas = _selectedProjectAreas.join(', ');
      final areaInfo = selectedAreas.isEmpty ? '所有區域' : selectedAreas;

      // 從API獲取樹種推薦
      // Refactored to use AiService
      final response = await _aiService.getSpeciesRecommendations(
        widget.userId,
        _selectedProjectAreas,
      );

      if (response['success'] == true) {
        final recommendations = response['recommendations'] ?? '無法獲取樹種推薦';
        setState(() {
          _messages.add(
            ChatMessage(
              role: 'user',
              content: '請推薦適合$areaInfo種植的樹種',
              isUser: true,
            ),
          );

          _messages.add(
            ChatMessage(
              role: 'assistant',
              content: recommendations,
              isUser: false,
            ),
          );
        });
      } else {
        throw '獲取樹種推薦失敗: ${response['message']}';
      }
      /*
      final response = await http.post(
        Uri.parse('http://172.20.10.4:3000/api/ai/species_recommendations'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'userId': widget.userId,
          'selectedAreas': _selectedProjectAreas,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final recommendations = data['recommendations'] ?? '無法獲取樹種推薦';

        // 向對話中添加樹種推薦
        setState(() {
          _messages.add(ChatMessage(
            role: 'user',
            content: '請推薦適合$areaInfo種植的樹種',
            isUser: true,
          ));

          _messages.add(ChatMessage(
            role: 'assistant',
            content: recommendations,
            isUser: false,
          ));
        });
      } else {
        throw '獲取樹種推薦失敗: ${response.statusCode}';
      }
      */
    } catch (e) {
      print('獲取樹種推薦時出錯: $e');
      final selectedAreas = _selectedProjectAreas.join(', ');
      final areaInfo = selectedAreas.isEmpty ? '所有區域' : selectedAreas;

      // 如果失敗，使用OpenAI直接生成推薦
      try {
        // This should be a backend call
        final treeData = await _fetchTreeData();
        final systemPrompt = '你是一位樹木與林業專家。以下是用戶的樹木數據: $treeData';
        final userPrompt = '請針對$areaInfo推薦5-10種適合種植的樹種，並說明每種樹木的特點、生長條件和碳吸收潛力。';
        // Commenting out direct OpenAI call
        /*
        // Legacy direct OpenAI call removed for security
        */
        throw '備用AI服務目前無法使用。';
      } catch (openAIError) {
        print('使用OpenAI獲取樹種推薦時出錯: $openAIError');
        setState(() {
          _messages.add(
            ChatMessage(
              role: 'user',
              content: '請推薦適合$areaInfo種植的樹種',
              isUser: true,
            ),
          );

          _messages.add(
            ChatMessage(
              role: 'assistant',
              content: '抱歉，目前無法獲取樹種推薦。請稍後再試或檢查網絡連接。',
              isUser: false,
            ),
          );
        });
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  // 獲取管理建議
  Future<void> _fetchManagementAdvice() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // 獲取已選擇的區域資料
      final selectedAreas = _selectedProjectAreas.join(', ');
      final areaInfo = selectedAreas.isEmpty ? '所有區域' : selectedAreas;

      // 從API獲取管理建議
      // Refactored to use AiService
      final response = await _aiService.getManagementAdvice(
        widget.userId,
        _selectedProjectAreas,
      );

      if (response['success'] == true) {
        final advice = response['advice'] ?? '無法獲取區域樹木管理建議';
        setState(() {
          _messages.add(
            ChatMessage(
              role: 'user',
              content: '請提供$areaInfo的樹木管理建議',
              isUser: true,
            ),
          );

          _messages.add(
            ChatMessage(role: 'assistant', content: advice, isUser: false),
          );
        });
      } else {
        throw '獲取管理建議失敗: ${response['message']}';
      }
      /*
      final response = await http.post(
        Uri.parse('http://172.20.10.4:3000/api/ai/management_advice'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'userId': widget.userId,
          'selectedAreas': _selectedProjectAreas,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final advice = data['advice'] ?? '無法獲取區域樹木管理建議';

        // 向對話中添加管理建議
        setState(() {
          _messages.add(ChatMessage(
            role: 'user',
            content: '請提供$areaInfo的樹木管理建議',
            isUser: true,
          ));

          _messages.add(ChatMessage(
            role: 'assistant',
            content: advice,
            isUser: false,
          ));
        });
      } else {
        throw '獲取管理建議失敗: ${response.statusCode}';
      }
      */
    } catch (e) {
      print('獲取管理建議時出錯: $e');
      final selectedAreas = _selectedProjectAreas.join(', ');
      final areaInfo = selectedAreas.isEmpty ? '所有區域' : selectedAreas;

      // 如果失敗，使用OpenAI直接生成建議
      try {
        final treeData = await _fetchTreeData();
        final systemPrompt = '你是一位樹木管理專家。以下是用戶的樹木數據: $treeData';
        final userPrompt = '請針對$areaInfo的樹木提供具體的管理建議，包括澆水、施肥、修剪和病蟲害防治等方面。';
        // Commenting out direct OpenAI call
        /*
        // Legacy direct OpenAI call removed for security
        */
        throw '備用AI服務目前無法使用。';
      } catch (openAIError) {
        print('使用OpenAI獲取建議時出錯: $openAIError');
        setState(() {
          _messages.add(
            ChatMessage(
              role: 'user',
              content: '請提供$areaInfo的樹木管理建議',
              isUser: true,
            ),
          );

          _messages.add(
            ChatMessage(
              role: 'assistant',
              content: '抱歉，目前無法獲取您區域的樹木管理建議。請稍後再試或檢查網絡連接。',
              isUser: false,
            ),
          );
        });
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  String _translateEfficiency(String efficiency) {
    switch (efficiency) {
      case 'high':
        return '高';
      case 'medium':
        return '中';
      case 'low':
        return '低';
      default:
        return efficiency;
    }
  }

  String _translateRate(String rate) {
    switch (rate) {
      case 'fast':
        return '快';
      case 'medium':
        return '中';
      case 'slow':
        return '慢';
      default:
        return rate;
    }
  }

  String _translateLifespan(String lifespan) {
    switch (lifespan) {
      case 'long':
        return '長';
      case 'medium':
        return '中';
      case 'short':
        return '短';
      default:
        return lifespan;
    }
  }

  String _translateMaintenance(String maintenance) {
    switch (maintenance) {
      case 'high':
        return '高';
      case 'medium':
        return '中';
      case 'low':
        return '低';
      default:
        return maintenance;
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _tabController.dispose();
    _activityAmountController.dispose(); // Dispose the new controller
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 永續碳匯助手'),
        backgroundColor: AppColors.surfaceLight,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false, // 修改此處，從 true 改為 false
          tabs: const [
            Tab(icon: Icon(Icons.chat), text: '助手聊天'),
            Tab(icon: Icon(Icons.compare_arrows), text: '樹種比較'),
            Tab(icon: Icon(Icons.calculate), text: '碳足跡計算'),
            Tab(
              icon: Icon(Icons.checklist_rtl_outlined),
              text: '管理建議',
            ), // New Tab
          ],
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.surfaceLight, Colors.white],
          ),
        ),
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildChatView(),
            _buildSpeciesComparisonView(),
            _buildCarbonFootprintView(),
            _buildManagementActionsView(), // New View
          ],
        ),
      ),
    );
  }

  Widget _buildChatView() {
    return Column(
      children: [
        // 模型選擇器
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text('選擇AI模型: ', style: TextStyle(fontSize: 12)),
              Expanded(
                // Wrap DropdownButton with Expanded
                child: DropdownButton<String>(
                  value: _selectedModel,
                  isExpanded: true,
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      setState(() {
                        _selectedModel = newValue;
                      });
                    }
                  },
                  items: _availableModels.entries.map<DropdownMenuItem<String>>(
                    (MapEntry<String, String> entry) {
                      return DropdownMenuItem<String>(
                        value: entry.value,
                        child: Text(entry.key),
                      );
                    },
                  ).toList(),
                ),
              ),
              const SizedBox(width: 8),
              const Text('知識庫'),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(8),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final message = _messages[index];
              return _MessageBubble(message: message);
            },
          ),
        ),
        if (_isLoading)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: AppColors.greenGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.eco_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.neutral200,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.forestGreen,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'AI 正在思考...',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.neutral600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        // 現代化輸入區域 v2.0
        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: AppColors.neutral200,
                    width: 1,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        maxLines: null,
                        decoration: InputDecoration(
                          hintText: '輸入訊息，向 AI 助手提問...',
                          hintStyle: TextStyle(
                            color: AppColors.neutral500,
                            fontSize: 15,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                        ),
                        style: TextStyle(
                          color: AppColors.neutral900,
                          fontSize: 15,
                          height: 1.4,
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8, bottom: 8),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: AppColors.greenGradient,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.forestGreen.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _sendMessage,
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              width: 44,
                              height: 44,
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.arrow_upward_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildQuickActionButton(
                      icon: Icons.eco,
                      label: '樹種推薦',
                      onPressed: () {
                        _fetchSpeciesRecommendations();
                      },
                    ),
                    const SizedBox(width: 10),
                    _buildQuickActionButton(
                      icon: Icons.emoji_nature,
                      label: '管理建議',
                      onPressed: () {
                        _tabController.animateTo(3);
                      },
                    ),
                    const SizedBox(width: 10),
                    _buildQuickActionButton(
                      icon: Icons.school,
                      label: '碳匯知識',
                      onPressed: () {
                        _showEducationTopicsDialog();
                      },
                    ),
                    const SizedBox(width: 10),
                    _buildQuickActionButton(
                      icon: Icons.compare_arrows,
                      label: '樹種比較',
                      onPressed: () {
                        _tabController.animateTo(1);
                      },
                    ),
                    const SizedBox(width: 10),
                    _buildQuickActionButton(
                      icon: Icons.tune,
                      label: '選擇區域',
                      onPressed: () {
                        _showAreaSelectionDialog();
                      },
                    ),
                    const SizedBox(width: 10),
                    _buildQuickActionButton(
                      icon: Icons.co2,
                      label: '碳足跡計算',
                      onPressed: () {
                        _tabController.animateTo(2);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.forestGreen.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: AppColors.forestGreen,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.forestGreen,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAreaSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) {
        // 創建本地變數暫存選中的區域
        List<String> tempSelectedAreas = List.from(_selectedProjectAreas);

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('選擇專案區位'),
              content: _isLoadingAreas
                  ? const Center(child: CircularProgressIndicator())
                  : SizedBox(
                      width: double.maxFinite,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _projectAreas.length,
                        itemBuilder: (context, index) {
                          final area = _projectAreas[index];
                          return CheckboxListTile(
                            title: Text(area),
                            value: tempSelectedAreas.contains(area),
                            onChanged: (bool? value) {
                              setState(() {
                                if (value == true) {
                                  tempSelectedAreas.add(area);
                                } else {
                                  tempSelectedAreas.remove(area);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () {
                    // 確認並更新選擇的區域
                    this.setState(() {
                      _selectedProjectAreas = List.from(tempSelectedAreas);
                    });
                    Navigator.pop(context);

                    // 提示用戶已選擇區域
                    if (_selectedProjectAreas.isNotEmpty) {
                      this.setState(() {
                        _messages.add(
                          ChatMessage(
                            role: 'assistant',
                            content:
                                '已選擇專案區位: ${_selectedProjectAreas.join(', ')}。\n\n您現在可以計算該區域的碳信用額度或獲取管理建議。',
                            isUser: false,
                          ),
                        );
                      });
                      _scrollToBottom();
                    }
                  },
                  child: const Text('確認'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSpeciesComparisonView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _speciesComparisonFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '樹種碳匯比較與推薦',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '選擇多個樹種和一個地區，查看它們在碳匯能力等方面的比較。',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 20),

            // Species Multi-Select Dropdown
            if (_isFetchingSpeciesList)
              const Center(child: CircularProgressIndicator())
            else if (_availableSpeciesForComparison.isNotEmpty)
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: '選擇比較樹種 (可多選)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.forest_outlined),
                ),
                child: InkWell(
                  onTap: () async {
                    final List<dynamic>? result =
                        await showDialog<List<dynamic>>(
                      context: context,
                      builder: (BuildContext context) {
                        List<dynamic> tempSelected = List.from(
                          _selectedSpeciesObjectsForComparison,
                        );
                        return StatefulBuilder(
                          builder: (context, setDialogState) {
                            return AlertDialog(
                              title: const Text('選擇樹種'),
                              content: SizedBox(
                                width: double.maxFinite,
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount:
                                      _availableSpeciesForComparison.length,
                                  itemBuilder: (context, index) {
                                    final species =
                                        _availableSpeciesForComparison[index];
                                    final isSelected = tempSelected.any(
                                      (s) => s['id'] == species['id'],
                                    );
                                    return CheckboxListTile(
                                      title: Text(
                                        species['common_name_zh'] ?? '未知樹種',
                                      ),
                                      value: isSelected,
                                      onChanged: (bool? value) {
                                        setDialogState(() {
                                          if (value == true) {
                                            tempSelected.add(species);
                                          } else {
                                            tempSelected.removeWhere(
                                              (s) => s['id'] == species['id'],
                                            );
                                          }
                                        });
                                      },
                                    );
                                  },
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('取消'),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, tempSelected),
                                  child: const Text('確定'),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    );
                    if (result != null) {
                      setState(() {
                        _selectedSpeciesObjectsForComparison = result;
                        _comparisonData = null;
                        _speciesComparisonError = null;
                      });
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    child: Text(
                      _selectedSpeciesObjectsForComparison.isEmpty
                          ? '請選擇樹種'
                          : _selectedSpeciesObjectsForComparison
                              .map((s) => s['common_name_zh'])
                              .join(', '),
                      style: TextStyle(
                        fontSize: 16,
                        color: _selectedSpeciesObjectsForComparison.isEmpty
                            ? Colors.grey.shade600
                            : Colors.black,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              )
            else
              const Text('無法載入樹種列表，請稍後再試。'),

            SizedBox(
              height: _selectedSpeciesObjectsForComparison.isEmpty ? 0 : 8,
            ),
            if (_selectedSpeciesObjectsForComparison.isEmpty &&
                _speciesComparisonFormKey.currentState?.validate() == false)
              Padding(
                padding: const EdgeInsets.only(left: 12.0, top: 4.0),
                child: Text(
                  '請至少選擇一個樹種',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Region Dropdown
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: '選擇比較區域',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.public_outlined),
              ),
              value: _selectedRegionCodeForComparison,
              hint: const Text('請選擇區域'),
              isExpanded: true,
              items: _availableRegionsForComparison.map((
                Map<String, String> region,
              ) {
                return DropdownMenuItem<String>(
                  value: region['code']!,
                  child: Text(region['name']!),
                );
              }).toList(),
              onChanged: (String? newValue) {
                setState(() {
                  _selectedRegionCodeForComparison = newValue;
                  _comparisonData = null;
                  _speciesComparisonError = null;
                });
              },
              validator: (value) => value == null ? '請選擇區域' : null,
            ),
            const SizedBox(height: 24),

            // Compare Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.compare_arrows_outlined),
                label: const Text('開始比較'),
                onPressed: _isFetchingComparisonData
                    ? null
                    : _fetchSpeciesComparisonData,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal, // Different color for this tab
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  textStyle: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Loading Indicator or Error Message
            if (_isFetchingComparisonData)
              const Center(child: CircularProgressIndicator()),
            if (_speciesComparisonError != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10.0),
                child: Text(
                  '錯誤: $_speciesComparisonError',
                  style: const TextStyle(color: Colors.red, fontSize: 14),
                ),
              ),

            // Results Display - Radar Chart and Table
            if (_comparisonData != null && _comparisonData!.isNotEmpty)
              _buildComparisonResultView(_comparisonData!),

            const SizedBox(height: 40), // Extra space at the bottom
          ],
        ),
      ),
    );
  }

  Widget _buildComparisonResultView(List<Map<String, dynamic>> data) {
    if (data.isEmpty) return const SizedBox.shrink();

    // Define the metrics and their display names for the radar chart
    // These keys must match what the backend returns in _comparisonData
    final Map<String, String> radarMetrics = {
      'avg_carbon_absorption': '年均碳吸存(kg)',
      'region_score': '區域評分(1-5)',
      'max_height_avg': '平均最大樹高(m)',
      'lifespan_avg': '平均壽命(年)',
      // Add more metrics if available and relevant, e.g., drought_tolerance converted to a numerical scale
    };

    // Normalize data for radar chart (example: 0-100 scale)
    // This needs careful implementation based on expected ranges of your metrics
    List<RadarDataSet> radarDataSets = [];
    final colors = [
      Colors.blue,
      Colors.red,
      Colors.purple,
      Colors.orange,
      Colors.brown,
    ];

    // Find min/max for each metric to normalize
    Map<String, double> minValues = {};
    Map<String, double> maxValues = {};

    radarMetrics.keys.forEach((metricKey) {
      double currentMin = double.maxFinite;
      double currentMax = double.minPositive;
      for (var speciesData in data) {
        final value = (speciesData[metricKey] as num?)?.toDouble() ?? 0.0;
        if (value < currentMin) currentMin = value;
        if (value > currentMax) currentMax = value;
      }
      // Handle case where all values are the same for a metric to avoid division by zero
      minValues[metricKey] = currentMin;
      maxValues[metricKey] =
          (currentMax == currentMin) ? currentMax + 1 : currentMax;
    });

    for (int i = 0; i < data.length; i++) {
      final speciesData = data[i];
      List<RadarEntry> entries = [];
      radarMetrics.keys.forEach((metricKey) {
        double rawValue = (speciesData[metricKey] as num?)?.toDouble() ?? 0.0;
        double minVal = minValues[metricKey]!;
        double maxVal = maxValues[metricKey]!;
        double normalizedValue = (maxVal - minVal == 0)
            ? 50
            : ((rawValue - minVal) / (maxVal - minVal) * 100);
        // Clamp value to be safe, e.g., between 0 and 100
        normalizedValue = normalizedValue.clamp(0, 100);
        entries.add(RadarEntry(value: normalizedValue));
      });

      radarDataSets.add(
        RadarDataSet(
          fillColor: colors[i % colors.length].withOpacity(0.2),
          borderColor: colors[i % colors.length],
          entryRadius: 3,
          dataEntries: entries,
          borderWidth: 2,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const Text(
          '樹種比較雷達圖',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.teal,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 300,
          child: RadarChart(
            RadarChartData(
              dataSets: radarDataSets,
              radarBackgroundColor: Colors.transparent,
              borderData: FlBorderData(show: false),
              radarBorderData: const BorderSide(color: Colors.grey),
              titleTextStyle: const TextStyle(
                color: Colors.black,
                fontSize: 10,
              ),
              getTitle: (index, angle) {
                // Make sure titles are short and readable
                return RadarChartTitle(
                  text: radarMetrics.values.elementAt(index).split('(')[0],
                  angle: angle,
                );
              },
              tickCount: 5, // 0, 25, 50, 75, 100
              ticksTextStyle: const TextStyle(color: Colors.grey, fontSize: 8),
              gridBorderData: const BorderSide(color: Colors.grey, width: 0.5),
            ),
            swapAnimationDuration: const Duration(milliseconds: 400),
          ),
        ),
        const SizedBox(height: 10),
        // Legend for Radar Chart
        Wrap(
          spacing: 8.0,
          children: List.generate(data.length, (index) {
            return Chip(
              avatar: CircleAvatar(
                backgroundColor: colors[index % colors.length],
                radius: 6,
              ),
              label: Text(
                data[index]['common_name_zh'] ?? '未知',
                style: const TextStyle(fontSize: 12),
              ),
              backgroundColor: colors[index % colors.length].withOpacity(0.1),
            );
          }),
        ),
        const SizedBox(height: 20),
        const Text(
          '詳細數據表',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.teal,
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 12,
            headingRowHeight: 40,
            dataRowMinHeight: 35,
            dataRowMaxHeight: 45,
            columns: const [
              DataColumn(
                label: Text(
                  '樹種',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataColumn(
                label: Text(
                  '年均碳吸存\n(kg CO₂/株)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataColumn(
                label: Text(
                  '區域評分',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataColumn(
                label: Text(
                  '生長速率',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataColumn(
                label: Text(
                  '平均最大樹高\n(m)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataColumn(
                label: Text(
                  '平均壽命\n(年)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataColumn(
                label: Text(
                  '耐旱性',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataColumn(
                label: Text(
                  '耐鹽性',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
            rows: data.map((species) {
              return DataRow(
                cells: [
                  DataCell(Text(species['common_name_zh'] ?? 'N/A')),
                  DataCell(
                    Text(
                      species['avg_carbon_absorption']?.toStringAsFixed(1) ??
                          'N/A',
                    ),
                  ),
                  DataCell(Text(species['region_score']?.toString() ?? 'N/A')),
                  DataCell(Text(species['growth_rate'] ?? 'N/A')),
                  DataCell(
                    Text(
                      species['max_height_avg']?.toStringAsFixed(1) ?? 'N/A',
                    ),
                  ),
                  DataCell(
                    Text(species['lifespan_avg']?.toStringAsFixed(0) ?? 'N/A'),
                  ),
                  DataCell(Text(species['drought_tolerance'] ?? 'N/A')),
                  DataCell(Text(species['salt_tolerance'] ?? 'N/A')),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildCarbonFootprintView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _carbonFootprintFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '碳足跡計算器',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '計算您日常活動產生的碳足跡，並了解需要多少樹木才能抵消這些排放。',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 20),

            // Activity Type Dropdown
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: '活動類型',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.local_activity),
              ),
              value: _selectedActivityType,
              hint: const Text('請選擇活動類型'),
              isExpanded: true,
              items: _activityTypes.map((String type) {
                return DropdownMenuItem<String>(
                  value: type,
                  child: Text(type, overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (String? newValue) {
                setState(() {
                  _selectedActivityType = newValue;
                  _selectedActivityUnit =
                      null; // Reset unit when activity type changes
                  _carbonFootprintResult = null; // Clear previous results
                  _footprintCalculationError = null;
                });
              },
              validator: (value) => value == null ? '請選擇活動類型' : null,
            ),
            const SizedBox(height: 16),

            // Amount TextField
            TextFormField(
              controller: _activityAmountController,
              decoration: const InputDecoration(
                labelText: '數量',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.format_list_numbered),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return '請輸入數量';
                }
                if (double.tryParse(value) == null) {
                  return '請輸入有效的數字';
                }
                if (double.parse(value) <= 0) {
                  return '數量必須大於0';
                }
                return null;
              },
              onChanged: (_) => setState(() {
                // Clear results on input change
                _carbonFootprintResult = null;
                _footprintCalculationError = null;
              }),
            ),
            const SizedBox(height: 16),

            // Unit Dropdown
            if (_selectedActivityType != null &&
                _activityUnits[_selectedActivityType!] != null)
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: '單位',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.straighten),
                ),
                value: _selectedActivityUnit,
                hint: const Text('請選擇單位'),
                isExpanded: true,
                items: _activityUnits[_selectedActivityType!]!.map((
                  String unit,
                ) {
                  return DropdownMenuItem<String>(
                    value: unit,
                    child: Text(unit),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedActivityUnit = newValue;
                    _carbonFootprintResult = null; // Clear previous results
                    _footprintCalculationError = null;
                  });
                },
                validator: (value) => value == null ? '請選擇單位' : null,
              ),
            const SizedBox(height: 24),

            // Calculate Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.calculate_outlined),
                label: const Text('計算碳足跡'),
                onPressed:
                    _isCalculatingFootprint ? null : _calculateCarbonFootprint,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.forestGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  textStyle: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Loading Indicator or Error Message
            if (_isCalculatingFootprint)
              const Center(child: CircularProgressIndicator()),
            if (_footprintCalculationError != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10.0),
                child: Text(
                  '計算錯誤: $_footprintCalculationError',
                  style: const TextStyle(color: Colors.red, fontSize: 14),
                ),
              ),

            // Results Display
            if (_carbonFootprintResult != null)
              _buildFootprintResultCard(_carbonFootprintResult!),

            const SizedBox(height: 40), // Extra space at the bottom
          ],
        ),
      ),
    );
  }

  Future<void> _calculateCarbonFootprint() async {
    if (!(_carbonFootprintFormKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_selectedActivityType == null ||
        _activityAmountController.text.isEmpty ||
        _selectedActivityUnit == null) {
      setState(() {
        _footprintCalculationError = '請填寫所有欄位。';
      });
      return;
    }

    setState(() {
      _isCalculatingFootprint = true;
      _carbonFootprintResult = null;
      _footprintCalculationError = null;
    });

    try {
      // Refactored to use a hypothetical method in CarbonService
      final response = await _carbonService.calculateCarbonFootprint(
        activityType: _selectedActivityType!,
        amount: double.parse(_activityAmountController.text),
        unit: _selectedActivityUnit!,
      );

      if (response['success'] == true) {
        setState(() {
          _carbonFootprintResult = response['data'];
        });
      } else {
        setState(() {
          _footprintCalculationError = response['message'] ?? '計算失敗，請稍後再試。';
        });
      }
      /*
      final response = await http.post(
        Uri.parse('http://172.20.10.4:3000/api/carbon-footprint/calculator'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: json.encode({
          'activityType': _selectedActivityType,
          'amount': double.parse(_activityAmountController.text),
          'unit': _selectedActivityUnit,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data['success'] == true) {
          setState(() {
            _carbonFootprintResult = data['data'];
          });
        } else {
          setState(() {
            _footprintCalculationError = data['message'] ?? '計算失敗，請稍後再試。';
          });
        }
      } else {
        final errorData = json.decode(utf8.decode(response.bodyBytes));
        setState(() {
          _footprintCalculationError =
              errorData['message'] ?? '伺服器錯誤: ${response.statusCode}';
        });
      }
      */
    } catch (e) {
      setState(() {
        _footprintCalculationError = '發生預期外的錯誤: $e';
      });
    } finally {
      setState(() {
        _isCalculatingFootprint = false;
      });
    }
  }

  Widget _buildFootprintResultCard(Map<String, dynamic> result) {
    final data = result; // API response is already the data object
    final offsetResults = data['offsetResults'] as Map<String, dynamic>?;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 10),
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
                color: Colors.green,
              ),
            ),
            const Divider(),
            _buildResultRow('活動類型:', '${data['activityType']}'),
            _buildResultRow('輸入數量:', '${data['amount']} ${data['unit']}'),
            const SizedBox(height: 10),
            _buildResultRow(
              '排放係數:',
              '${data['emissionFactor']?.toStringAsFixed(4)} kg CO₂-eq/${data['unit']}',
            ),
            _buildResultRow('係數來源:', '${data['factorSource']}', isSmall: true),
            if (data.containsKey('indirectEmissionFactor')) ...[
              const SizedBox(height: 5),
              _buildResultRow(
                '間接排放係數:',
                '${data['indirectEmissionFactor']?.toStringAsFixed(4)} kg CO₂-eq/${data['unit']}',
              ),
              _buildResultRow(
                '間接係數來源:',
                '${data['indirectFactorSource']}',
                isSmall: true,
              ),
            ],
            const SizedBox(height: 10),
            _buildResultRow('計算公式:', '${data['formula']}', isSmall: true),
            const SizedBox(height: 10),
            _buildResultRow(
              '直接碳排放:',
              '${data['carbonFootprintDirect']?.toStringAsFixed(2)} ${data['resultUnit']}',
              highlight: true,
            ),
            if (data.containsKey('carbonFootprintIndirect'))
              _buildResultRow(
                '間接碳排放:',
                '${data['carbonFootprintIndirect']?.toStringAsFixed(2)} ${data['resultUnit']}',
                highlight: true,
              ),
            _buildResultRow(
              '總碳排放量:',
              '${data['carbonFootprintTotal']?.toStringAsFixed(2)} ${data['resultUnit']}',
              highlight: true,
              bold: true,
            ),
            if (offsetResults != null) ...[
              const SizedBox(height: 15),
              const Text(
                '碳抵銷建議',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal,
                ),
              ),
              const Divider(color: Colors.teal),
              _buildResultRow(
                '總排放量(公斤):',
                '${offsetResults['carbonFootprintKg']?.toStringAsFixed(2)} kg CO₂-eq',
              ),
              if (offsetResults['treesNeededForOneYear'] != null)
                _buildResultRow(
                  '一年需種植樹木:',
                  '${offsetResults['treesNeededForOneYear']} 棵',
                ),
              if (offsetResults['treesNeededFor10Years'] != null)
                _buildResultRow(
                  '十年需種植樹木:',
                  '${offsetResults['treesNeededFor10Years']} 棵',
                ),
              if (offsetResults['treesNeededFor20Years'] != null)
                _buildResultRow(
                  '二十年需種植樹木:',
                  '${offsetResults['treesNeededFor20Years']} 棵',
                ),
              if (offsetResults['speciesComparison'] != null &&
                  (offsetResults['speciesComparison'] as Map).isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text(
                  '不同樹種抵銷建議 (一年):',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                ...(offsetResults['speciesComparison'] as Map<String, dynamic>)
                    .entries
                    .map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(left: 8.0, top: 2.0),
                    child: Text('  • ${entry.key}: ${entry.value} 棵'),
                  );
                }).toList(),
              ],
              const SizedBox(height: 10),
              if (offsetResults['note'] != null)
                Text(
                  '備註: ${offsetResults['note']}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultRow(
    String label,
    String value, {
    bool highlight = false,
    bool bold = false,
    bool isSmall = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: Colors.black87,
              fontSize: isSmall ? 12 : 14,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                color: highlight ? Colors.deepOrangeAccent : Colors.black,
                fontSize: isSmall ? 12 : 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 顯示碳匯教育主題選擇對話框
  void _showEducationTopicsDialog() {
    final topics = {
      '碳循環': '了解森林與樹木在全球碳循環中的作用',
      '計算方法': '碳儲存與碳吸存量計算方法詳解',
      '樹種比較': '不同樹種的碳吸存能力比較',
      '管理策略': '最大化碳匯效益的森林管理策略',
    };

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('選擇碳匯知識主題'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: topics.length,
              itemBuilder: (context, index) {
                final topic = topics.keys.elementAt(index);
                final description = topics[topic];
                return ListTile(
                  title: Text(topic),
                  subtitle: Text(description ?? ''),
                  onTap: () {
                    Navigator.pop(context);
                    _fetchCarbonEducation(topic);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );
  }

  // 獲取碳匯教育內容
  Future<void> _fetchCarbonEducation(String topic) async {
    try {
      setState(() {
        _isLoading = true;
      });

      // Refactored to use a hypothetical method in CarbonService
      final response = await _carbonService.getCarbonEducation(topic);

      if (response['success'] == true) {
        setState(() {
          _messages.add(
            ChatMessage(
              role: 'assistant',
              content: '**$topic - 碳匯知識**\n\n${response['content']}',
              isUser: false,
            ),
          );
        });
      } else {
        throw '獲取教育內容失敗';
      }
      /*
      final response = await http.get(
        Uri.parse('http://172.20.10.4:3000/api/carbon-education/$topic'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          setState(() {
            _messages.add(ChatMessage(
              role: 'assistant',
              content: '**$topic - 碳匯知識**\n\n${data['content']}',
              isUser: false,
            ));
          });
        } else {
          throw '獲取教育內容失敗';
        }
      } else {
        throw '伺服器錯誤：${response.statusCode}';
      }
      */
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(
            ChatMessage(
              role: 'assistant',
              content: '抱歉，獲取碳匯知識時發生錯誤：$e',
              isUser: false,
            ),
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _scrollToBottom();
      }
    }
  }

  // 顯示樹種比較對話框
  Future<void> _showSpeciesComparisonDialog(BuildContext context) async {
    final allSpecies = await _fetchTreeSpecies();
    if (allSpecies.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('無法獲取樹種資料')));
      return;
    }
    List<dynamic> selectedSpecies = [];
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('樹種比較'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: allSpecies.length,
                  itemBuilder: (context, index) {
                    final species = allSpecies[index];
                    final isSelected = selectedSpecies.contains(species);
                    return CheckboxListTile(
                      title: Text(species['name'] ?? '未知樹種'),
                      value: isSelected,
                      onChanged: (bool? value) {
                        setState(() {
                          if (value == true) {
                            selectedSpecies.add(species);
                          } else {
                            selectedSpecies.remove(species);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, selectedSpecies),
                  child: const Text('比較'),
                ),
              ],
            );
          },
        );
      },
    ).then((selectedSpecies) async {
      if (selectedSpecies != null && selectedSpecies.isNotEmpty) {
        await _performSpeciesComparison(selectedSpecies);
      }
    });
  }

  // 從API獲取所有樹種
  Future<List<dynamic>> _fetchTreeSpecies() async {
    try {
      // Refactored to use a hypothetical TreeSpeciesService
      final response = await _speciesService.getSpecies();
      if (response.isNotEmpty) {
        return response;
      } else {
        throw '獲取樹種數據失敗';
      }
      /*
      final response = await http.get(
        Uri.parse('http://172.20.10.4:3000/api/tree_species'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data['success'] == true && data['data'] != null) {
          return data['data'];
        } else {
          throw data['error'] ?? '獲取樹種數據失敗';
        }
      } else {
        throw '伺服器錯誤：${response.statusCode}';
      }
      */
    } catch (e) {
      print('獲取樹種數據時出錯: $e');
      return [];
    }
  }

  // 執行樹種比較
  Future<void> _performSpeciesComparison(List<dynamic> selectedSpecies) async {
    try {
      setState(() {
        _isLoading = true;
      });

      // 準備樹種名稱列表
      final speciesNames = selectedSpecies
          .map<String>((species) => (species['name'] ?? '未知樹種') as String)
          .toList();

      // 從API獲取比較結果
      // Refactored to use AiService
      final response = await _aiService.compareSpecies(speciesNames);

      if (response['success'] == true) {
        final comparison = response['comparison'] ?? '無法獲取樹種比較結果';
        setState(() {
          _messages.add(
            ChatMessage(
              role: 'user',
              content: '請比較以下樹種: ${speciesNames.join(', ')}',
              isUser: true,
            ),
          );

          _messages.add(
            ChatMessage(role: 'assistant', content: comparison, isUser: false),
          );
        });
      } else {
        setState(() {
          _messages.add(
            ChatMessage(
              role: 'assistant',
              content: '抱歉，無法獲取樹種比較結果。',
              isUser: false,
            ),
          );
        });
      }
      /*
      final response = await http.post(
        Uri.parse('http://172.20.10.4:3000/api/ai/species_comparison'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'species': speciesNames,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final comparison = data['comparison'] ?? '無法獲取樹種比較結果';

        // 向對話中添加樹種比較結果
        setState(() {
          _messages.add(ChatMessage(
            role: 'user',
            content: '請比較以下樹種: ${speciesNames.join(', ')}',
            isUser: true,
          ));

          _messages.add(ChatMessage(
            role: 'assistant',
            content: comparison,
            isUser: false,
          ));
        });
      } else {
        setState(() {
          _messages.add(ChatMessage(
            role: 'assistant',
            content: '抱歉，無法獲取樹種比較結果。',
            isUser: false,
          ));
        });
      }
      */
    } catch (e) {
      setState(() {
        _messages.add(
          ChatMessage(
            role: 'assistant',
            content: '抱歉，獲取樹種比較時發生錯誤。',
            isUser: false,
          ),
        );
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  List<FlSpot> _getHistoricPriceSpots(List<dynamic> prices) {
    return List.generate(prices.length, (index) {
      return FlSpot(index.toDouble(), prices[index].toDouble());
    });
  }

  String _translateTrend(String trend) {
    switch (trend) {
      case 'up':
        return '上升';
      case 'down':
        return '下降';
      case 'stable':
        return '穩定';
      default:
        return trend;
    }
  }

  String _translateForecast(String forecast) {
    switch (forecast) {
      case 'rising':
        return '預計繼續上升';
      case 'falling':
        return '預計將下降';
      case 'stable':
        return '預計保持穩定';
      default:
        return forecast;
    }
  }

  String _formatDateTime(String dateTimeStr) {
    try {
      final dateTime = DateTime.parse(dateTimeStr);
      return '${dateTime.year}/${dateTime.month}/${dateTime.day} ${dateTime.hour}:${dateTime.minute}';
    } catch (e) {
      return dateTimeStr;
    }
  }

  Widget _buildReportCard({required String title, required Widget child}) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const Divider(),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildReportRow(
    String label,
    String value, {
    bool highlight = false,
    bool bold = false,
    bool isSmall = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: Colors.black87,
              fontSize: isSmall ? 12 : 14,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                color: highlight ? Colors.deepOrangeAccent : Colors.black,
                fontSize: isSmall ? 12 : 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // === Species Comparison Tab ===
  Future<void> _fetchAvailableSpeciesForComparison() async {
    setState(() {
      _isFetchingSpeciesList = true;
      _speciesComparisonError = null;
    });
    try {
      // Refactored to use CarbonDataService
      final response = await _carbonDataService.getSpeciesList();
      if (response['success'] == true && response['data'] != null) {
        setState(() {
          _availableSpeciesForComparison = List<Map<String, dynamic>>.from(
            response['data'],
          );
        });
      } else {
        throw Exception(response['message'] ?? '無法獲取樹種列表');
      }
      /*
      final response = await http.get(
        Uri.parse('http://172.20.10.4:3000/api/tree-carbon-data/species-list'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
      );
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data['success'] == true && data['data'] != null) {
          setState(() {
            _availableSpeciesForComparison =
                List<Map<String, dynamic>>.from(data['data']);
          });
        } else {
          throw Exception(data['message'] ?? '無法獲取樹種列表');
        }
      } else {
        throw Exception('伺服器錯誤 ${response.statusCode}');
      }
      */
    } catch (e) {
      setState(() {
        _speciesComparisonError = '獲取樹種列表失敗: $e';
      });
    } finally {
      setState(() {
        _isFetchingSpeciesList = false;
      });
    }
  }

  Future<void> _fetchSpeciesComparisonData() async {
    if (!(_speciesComparisonFormKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_selectedSpeciesObjectsForComparison.isEmpty ||
        _selectedRegionCodeForComparison == null) {
      setState(() {
        _speciesComparisonError = '請選擇至少一個樹種和一個區域進行比較。';
      });
      return;
    }

    setState(() {
      _isFetchingComparisonData = true;
      _comparisonData = null;
      _speciesComparisonError = null;
    });

    try {
      List<int> speciesIds = _selectedSpeciesObjectsForComparison
          .map((s) => s['id'] as int)
          .toList();

      // Refactored to use a hypothetical method in AiService or a new SpeciesComparisonService
      final response = await ApiService.post('species-comparison/details', {
        'species_ids': speciesIds,
        'region_code': _selectedRegionCodeForComparison,
      });

      if (response['success'] == true && response['data'] != null) {
        setState(() {
          _comparisonData = List<Map<String, dynamic>>.from(response['data']);
        });
      } else {
        throw Exception(response['message'] ?? '獲取比較數據失敗');
      }
      /*
      final response = await http.post(
        Uri.parse('http://172.20.10.4:3000/api/species-comparison/details'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: json.encode({
          'species_ids': speciesIds,
          'region_code': _selectedRegionCodeForComparison,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data['success'] == true && data['data'] != null) {
          setState(() {
            _comparisonData = List<Map<String, dynamic>>.from(data['data']);
          });
        } else {
          throw Exception(data['message'] ?? '獲取比較數據失敗');
        }
      } else {
        final errorData = json.decode(utf8.decode(response.bodyBytes));
        throw Exception(errorData['message'] ?? '伺服器錯誤 ${response.statusCode}');
      }
      */
    } catch (e) {
      setState(() {
        _speciesComparisonError = '獲取比較數據時發生錯誤: $e';
      });
    } finally {
      setState(() {
        _isFetchingComparisonData = false;
      });
    }
  }
  // === END Species Comparison Tab ===

  // === Management Actions Tab ===
  Future<void> _fetchManagementActions({bool resetOffset = false}) async {
    if (resetOffset) {
      setState(() {
        _managementActionsOffset = 0;
        _managementActions = []; // Clear current actions when resetting
        _managementActionsTotal = 0;
      });
    }

    setState(() {
      _isLoadingManagementActions = true;
      _managementActionsError = null;
    });

    try {
      // Refactored to use ManagementService
      final response = await _managementService.getManagementActions(
        filters: _managementActionFilters,
        limit: _managementActionsLimit,
        offset: _managementActionsOffset,
      );

      if (response['success'] == true) {
        final newActions = List<Map<String, dynamic>>.from(response['data']);
        setState(() {
          if (resetOffset) {
            _managementActions = newActions;
          } else {
            _managementActions.addAll(newActions);
          }
          _managementActionsTotal = response['total'] ?? 0;
          _managementActionsOffset = _managementActions.length;
        });
      } else {
        throw Exception(response['message'] ?? '無法獲取管理建議');
      }
      /*
      Uri uri =
          Uri.parse('http://172.20.10.4:3000/api/tree-management/actions');
      Map<String, String> queryParams = {
        'limit': _managementActionsLimit.toString(),
        'offset': _managementActionsOffset.toString(),
      };

      if (_managementActionFilters['area_name'] != null) {
        queryParams['area_name'] = _managementActionFilters['area_name']!;
      }
      if (_managementActionFilters['is_done'] != null) {
        queryParams['is_done'] =
            _managementActionFilters['is_done']!.toString();
      }
      if (_managementActionFilters['category'] != null) {
        queryParams['category'] = _managementActionFilters['category']!;
      }

      final response = await http.get(
        uri.replace(queryParameters: queryParams),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data['success'] == true) {
          final newActions = List<Map<String, dynamic>>.from(data['data']);
          setState(() {
            if (resetOffset) {
              _managementActions = newActions;
            } else {
              _managementActions.addAll(newActions);
            }
            _managementActionsTotal = data['total'] ?? 0;
            _managementActionsOffset = _managementActions.length;
          });
        } else {
          throw Exception(data['message'] ?? '無法獲取管理建議');
        }
      } else {
        throw Exception('伺服器錯誤 ${response.statusCode}');
      }
      */
    } catch (e) {
      setState(() {
        _managementActionsError = '獲取管理建議失敗: $e';
      });
    } finally {
      setState(() {
        _isLoadingManagementActions = false;
      });
    }
  }

  Future<void> _updateManagementActionStatus(
    int actionId,
    bool isDone,
    int listIndex,
  ) async {
    try {
      // Refactored to use ManagementService
      final response = await _managementService.updateActionStatus(
        actionId,
        isDone,
      );

      if (response['success'] == true) {
        setState(() {
          _managementActions[listIndex]['is_done'] = isDone ? 1 : 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('建議 #${actionId} 狀態已更新'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw Exception(response['message'] ?? '更新狀態失敗');
      }
      /*
      final response = await http.put(
        Uri.parse(
            'http://172.20.10.4:3000/api/tree-management/actions/$actionId'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: json.encode({'is_done': isDone}),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          setState(() {
            _managementActions[listIndex]['is_done'] = isDone ? 1 : 0;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('建議 #${actionId} 狀態已更新'),
                backgroundColor: Colors.green),
          );
        } else {
          throw Exception(data['message'] ?? '更新狀態失敗');
        }
      } else {
        throw Exception('伺服器錯誤 ${response.statusCode}');
      }
      */
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('更新建議 #${actionId} 狀態失敗: $e'),
          backgroundColor: Colors.red,
        ),
      );
      // Optionally, revert checkbox state if API call fails
      setState(() {
        _managementActions[listIndex]['is_done'] = !isDone ? 1 : 0;
      });
    }
  }

  Future<void> _generateNewActions(String? areaName) async {
    if (areaName == null || areaName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('請選擇一個區域以生成建議'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() {
      _isLoadingManagementActions = true; // Use the general loading for now
    });
    try {
      // Refactored to use ManagementService
      final response = await _managementService.generateNewActions(
        areaName,
        widget.userId,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response['message'] ?? '建議生成請求已發送'),
          backgroundColor: Colors.green,
        ),
      );
      _fetchManagementActions(resetOffset: true); // Refresh list
      /*
      final response = await http.post(
        Uri.parse(
            'http://172.20.10.4:3000/api/tree-management/actions/generate'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: json.encode({
          'area_name': areaName,
          'user_id': widget.userId, // Pass userId if available
        }),
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = json.decode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(data['message'] ?? '建議生成請求已發送'),
              backgroundColor: Colors.green),
        );
        _fetchManagementActions(resetOffset: true); // Refresh list
      } else {
        final errorData = json.decode(response.body);
        throw Exception(
            errorData['message'] ?? '生成建議失敗 ${response.statusCode}');
      }
      */
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成建議時發生錯誤: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() {
        _isLoadingManagementActions = false;
      });
    }
  }

  Future<void> _deleteManagementAction(int actionId, int listIndex) async {
    bool? confirmDelete = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('確認刪除'),
          content: Text('您確定要刪除建議 #${actionId} 嗎？此操作無法復原。'),
          actions: <Widget>[
            TextButton(
              child: const Text('取消'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: const Text('刪除', style: TextStyle(color: Colors.red)),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );

    if (confirmDelete == true) {
      try {
        // Refactored to use ManagementService
        final response = await _managementService.deleteAction(actionId);
        if (response['success'] == true) {
          setState(() {
            _managementActions.removeAt(listIndex);
            _managementActionsTotal =
                _managementActionsTotal > 0 ? _managementActionsTotal - 1 : 0;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('建議 #${actionId} 已刪除'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          throw Exception(response['message'] ?? '刪除失敗');
        }
        /*
        final response = await http.delete(
          Uri.parse(
              'http://172.20.10.4:3000/api/tree-management/actions/$actionId'),
        );
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success'] == true) {
            setState(() {
              _managementActions.removeAt(listIndex);
              _managementActionsTotal =
                  _managementActionsTotal > 0 ? _managementActionsTotal - 1 : 0;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text('建議 #${actionId} 已刪除'),
                  backgroundColor: Colors.green),
            );
          } else {
            throw Exception(data['message'] ?? '刪除失敗');
          }
        } else {
          throw Exception('伺服器錯誤 ${response.statusCode}');
        }
        */
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('刪除建議 #${actionId} 失敗: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildManagementActionsView() {
    return Column(
      children: [
        // Filters
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: ExpansionTile(
            title: const Text(
              '篩選與操作',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            initiallyExpanded: false,
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      decoration: const InputDecoration(
                        labelText: '區域',
                        border: OutlineInputBorder(),
                      ),
                      value: _managementActionFilters['area_name'],
                      hint: const Text('所有區域'),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('所有區域'),
                        ),
                      ]..addAll(
                          _projectAreasForFiltering.map(
                            (area) => DropdownMenuItem(
                              value: area,
                              child: Text(area),
                            ),
                          ),
                        ),
                      onChanged: (value) {
                        setState(() {
                          _managementActionFilters['area_name'] = value;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<bool?>(
                      decoration: const InputDecoration(
                        labelText: '完成狀態',
                        border: OutlineInputBorder(),
                      ),
                      value: _managementActionFilters['is_done'],
                      hint: const Text('全部狀態'),
                      items: const [
                        DropdownMenuItem<bool?>(
                          value: null,
                          child: Text('全部狀態'),
                        ),
                        DropdownMenuItem<bool?>(
                          value: false,
                          child: Text('待處理'),
                        ),
                        DropdownMenuItem<bool?>(
                          value: true,
                          child: Text('已完成'),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _managementActionFilters['is_done'] = value;
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                decoration: const InputDecoration(
                  labelText: '建議分類',
                  border: OutlineInputBorder(),
                ),
                value: _managementActionFilters['category'],
                hint: const Text('所有分類'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('所有分類'),
                  ),
                ]..addAll(
                    _actionCategories.map(
                      (cat) => DropdownMenuItem(value: cat, child: Text(cat)),
                    ),
                  ),
                onChanged: (value) {
                  setState(() {
                    _managementActionFilters['category'] = value;
                  });
                },
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.filter_list),
                    label: const Text('套用篩選'),
                    onPressed: () => _fetchManagementActions(resetOffset: true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add_comment_outlined),
                    label: const Text('生成新建議'),
                    onPressed: () {
                      // Show dialog to select area for generating actions
                      String? selectedAreaForGeneration;
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('選擇區域以生成建議'),
                          content: DropdownButtonFormField<String>(
                            items: _projectAreasForFiltering
                                .map(
                                  (area) => DropdownMenuItem(
                                    value: area,
                                    child: Text(area),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) => selectedAreaForGeneration = val,
                            decoration: const InputDecoration(
                              labelText: '選擇區域',
                            ),
                            validator: (val) => val == null ? '請選擇一個區域' : null,
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('取消'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                if (selectedAreaForGeneration != null) {
                                  _generateNewActions(
                                    selectedAreaForGeneration,
                                  );
                                }
                              },
                              child: const Text('生成'),
                            ),
                          ],
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.portBlue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Loading or Error for list
        if (_isLoadingManagementActions && _managementActions.isEmpty)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_managementActionsError != null && _managementActions.isEmpty)
          Expanded(
            child: Center(
              child: Text(
                _managementActionsError!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          )
        else if (_managementActions.isEmpty)
          const Expanded(child: Center(child: Text('目前沒有管理建議。')))
        else
          // List of actions
          Expanded(
            child: ListView.builder(
              itemCount: _managementActions.length +
                  (_managementActions.length < _managementActionsTotal ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _managementActions.length) {
                  return _isLoadingManagementActions
                      ? const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : Center(
                          child: TextButton(
                            onPressed: () => _fetchManagementActions(),
                            child: const Text('載入更多建議'),
                          ),
                        );
                }
                final action = _managementActions[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: ListTile(
                    title: Text(
                      action['action_text'] ?? 'N/A',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('分類: ${action['category'] ?? 'N/A'}'),
                        Text(
                          '樹木ID: ${action['tree_id']} (${action['樹種名稱'] ?? '未知樹種'})',
                        ),
                        Text(
                          '專案: ${action['專案名稱'] ?? action['專案代碼'] ?? 'N/A'} (${action['專案區位'] ?? 'N/A'})',
                        ),
                        Text(
                          '建立時間: ${action['created_at'] != null ? DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(action['created_at'])) : 'N/A'}',
                        ),
                        if (action['due_date'] != null)
                          Text(
                            '預計完成: ${DateFormat('yyyy-MM-dd').format(DateTime.parse(action['due_date']))}',
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: action['is_done'] == 1,
                          onChanged: (bool? newValue) {
                            if (newValue != null) {
                              _updateManagementActionStatus(
                                action['action_id'],
                                newValue,
                                index,
                              );
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.redAccent,
                          ),
                          onPressed: () => _deleteManagementAction(
                            action['action_id'],
                            index,
                          ),
                        ),
                      ],
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  // === END Management Actions Tab ===
}
