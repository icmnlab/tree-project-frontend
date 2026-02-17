import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart'; // [NEW] 查詢結果視覺化
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import '../services/ai_service.dart';
import '../constants/colors.dart'; // [NEW] 統一色彩

/// 現代化 AI 聊天頁面 v2.0
/// 設計參考: ChatGPT, Claude, Gemini
/// 
/// 特色:
/// - 極簡現代化介面設計
/// - 漸層背景與毛玻璃效果
/// - 流暢的動畫過渡
/// - 優雅的打字動畫
/// - 精緻的對話氣泡設計
/// - 智慧建議卡片

// ============================================
// 資料模型
// ============================================

/// [NEW] 圖表資料模型 (用於查詢結果視覺化)
class ChartData {
  final String type; // 'bar' or 'pie'
  final String labelKey;
  final String valueKey;
  final List<ChartDataItem> data;

  ChartData({
    required this.type,
    required this.labelKey,
    required this.valueKey,
    required this.data,
  });

  factory ChartData.fromJson(Map<String, dynamic> json) {
    return ChartData(
      type: json['type'] as String? ?? 'bar',
      labelKey: json['labelKey'] as String? ?? '',
      valueKey: json['valueKey'] as String? ?? '',
      data: (json['data'] as List<dynamic>?)
              ?.map((e) => ChartDataItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class ChartDataItem {
  final String label;
  final double value;

  ChartDataItem({required this.label, required this.value});

  factory ChartDataItem.fromJson(Map<String, dynamic> json) {
    return ChartDataItem(
      label: json['label']?.toString() ?? '',
      value: (json['value'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// 單一對話訊息
class ChatMessage {
  final String id;
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final bool isLoading;
  final bool isError;
  final List<Map<String, dynamic>>? sources;
  final String? executedSQL;
  final ChartData? chartData; // [NEW] 可選的圖表資料
  final List<Map<String, dynamic>>? suggestions; // [NEW] 智慧建議
  final List<Map<String, dynamic>>? anomalies; // [NEW] 異常警示

  ChatMessage({
    String? id,
    required this.content,
    required this.isUser,
    DateTime? timestamp,
    this.isLoading = false,
    this.isError = false,
    this.sources,
    this.executedSQL,
    this.chartData,
    this.suggestions,
    this.anomalies,
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        timestamp = timestamp ?? DateTime.now();

  ChatMessage copyWith({
    String? content,
    bool? isLoading,
    bool? isError,
    List<Map<String, dynamic>>? sources,
    String? executedSQL,
    ChartData? chartData,
    List<Map<String, dynamic>>? suggestions,
    List<Map<String, dynamic>>? anomalies,
  }) {
    return ChatMessage(
      id: id,
      content: content ?? this.content,
      isUser: isUser,
      timestamp: timestamp,
      isLoading: isLoading ?? this.isLoading,
      isError: isError ?? this.isError,
      sources: sources ?? this.sources,
      executedSQL: executedSQL ?? this.executedSQL,
      chartData: chartData ?? this.chartData,
      suggestions: suggestions ?? this.suggestions,
      anomalies: anomalies ?? this.anomalies,
    );
  }
}

/// 對話會話
class ChatSession {
  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  List<ChatMessage> messages;

  ChatSession({
    String? id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<ChatMessage>? messages,
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        title = title ?? '新對話',
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        messages = messages ?? [];

  /// 根據第一條用戶訊息自動生成標題
  void updateTitleFromFirstMessage() {
    final firstUserMessage = messages.firstWhere(
      (m) => m.isUser,
      orElse: () => ChatMessage(content: '新對話', isUser: true),
    );
    String newTitle = firstUserMessage.content;
    if (newTitle.length > 30) {
      newTitle = '${newTitle.substring(0, 30)}...';
    }
    title = newTitle;
  }

  /// 轉換為 JSON（用於本地儲存）
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'messages': messages.map((m) => {
      'id': m.id,
      'content': m.content,
      'isUser': m.isUser,
      'timestamp': m.timestamp.toIso8601String(),
      'isError': m.isError,
    }).toList(),
  };

  /// 從 JSON 還原
  factory ChatSession.fromJson(Map<String, dynamic> json) {
    return ChatSession(
      id: json['id'],
      title: json['title'],
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
      messages: (json['messages'] as List).map((m) => ChatMessage(
        id: m['id'],
        content: m['content'],
        isUser: m['isUser'],
        timestamp: DateTime.parse(m['timestamp']),
        isError: m['isError'] ?? false,
      )).toList(),
    );
  }
}

// ============================================
// 主頁面
// ============================================

class AIChatPage extends StatefulWidget {
  final String userId;
  final List<String> selectedProjectAreas;

  const AIChatPage({
    super.key,
    required this.userId,
    this.selectedProjectAreas = const [],
  });

  @override
  State<AIChatPage> createState() => _AIChatPageState();
}

class _AIChatPageState extends State<AIChatPage> with TickerProviderStateMixin {
  // Services
  final AiService _aiService = AiService();

  // Controllers
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

  // State
  List<ChatSession> _sessions = [];
  ChatSession? _currentSession;
  bool _isLoading = false;
  bool _isSidebarOpen = false; // 預設收合，避免遮擋內容
  bool _isDarkMode = false;

  // Settings
  String _selectedModel = 'deepseek-ai/DeepSeek-V3';
  
  // 模型分類：SiliconFlow 免費額度 / 付費 API
  final Map<String, Map<String, dynamic>> _modelCategories = {
    '🆓 SiliconFlow 免費': {
      'models': {
        'deepseek-ai/DeepSeek-V3': 'DeepSeek V3 ⭐推薦',
        'Qwen/Qwen3-235B-A22B-Instruct': 'Qwen3 235B (最強)',
        'Qwen/QwQ-32B': 'QwQ 32B (推理)',
        'deepseek-ai/DeepSeek-R1-0528': 'DeepSeek R1 (推理)',
        'Qwen/Qwen3-32B-Instruct': 'Qwen3 32B',
      },
    },
    '💰 OpenAI GPT-5 (付費)': {
      'models': {
        'gpt-5-nano': 'GPT-5 Nano (最快)',
        'gpt-5-mini': 'GPT-5 Mini',
        'gpt-5.1': 'GPT-5.1 (最強)',
      },
    },
    '💰 Google Gemini (付費)': {
      'models': {
        'gemini-2.5-flash': 'Gemini 2.5 Flash',
        'gemini-2.5-pro': 'Gemini 2.5 Pro',
      },
    },
  };
  
  // 整合所有模型
  Map<String, String> get _availableModels {
    final models = <String, String>{};
    for (final category in _modelCategories.values) {
      models.addAll(Map<String, String>.from(category['models'] as Map));
    }
    return models;
  }

  // Animation
  late AnimationController _typingAnimationController;
  
  // 本地儲存 key
  static const String _sessionsStorageKey = 'ai_chat_sessions';

  @override
  void initState() {
    super.initState();
    _typingAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    // 載入本地儲存的對話歷史
    _loadSessions();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    _typingAnimationController.dispose();
    // 儲存對話歷史
    _saveSessions();
    super.dispose();
  }
  
  /// 從本地儲存載入對話歷史
  Future<void> _loadSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionsJson = prefs.getString(_sessionsStorageKey);
      
      if (sessionsJson != null) {
        final List<dynamic> decoded = jsonDecode(sessionsJson);
        final loadedSessions = decoded
            .map((json) => ChatSession.fromJson(json))
            .toList();
        
        // 只保留最近 7 天的對話
        final cutoff = DateTime.now().subtract(const Duration(days: 7));
        final recentSessions = loadedSessions
            .where((s) => s.updatedAt.isAfter(cutoff))
            .toList();
        
        if (recentSessions.isNotEmpty) {
          setState(() {
            _sessions = recentSessions;
            _currentSession = recentSessions.first;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('載入對話歷史失敗: $e');
    }
    
    // 如果沒有歷史或載入失敗，建立新對話
    _createNewSession();
  }
  
  /// 儲存對話歷史到本地
  Future<void> _saveSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 只保留最近 10 個對話
      final sessionsToSave = _sessions.take(10).toList();
      final sessionsJson = jsonEncode(
        sessionsToSave.map((s) => s.toJson()).toList()
      );
      await prefs.setString(_sessionsStorageKey, sessionsJson);
    } catch (e) {
      debugPrint('儲存對話歷史失敗: $e');
    }
  }

  // ============================================
  // 對話管理
  // ============================================

  void _createNewSession() {
    final newSession = ChatSession();
    setState(() {
      _sessions.insert(0, newSession);
      _currentSession = newSession;
    });
  }

  void _selectSession(ChatSession session) {
    setState(() {
      _currentSession = session;
    });
    // 滾動到底部
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  void _deleteSession(ChatSession session) {
    setState(() {
      _sessions.remove(session);
      if (_currentSession == session) {
        _currentSession = _sessions.isNotEmpty ? _sessions.first : null;
        if (_currentSession == null) {
          _createNewSession();
        }
      }
    });
    _saveSessions(); // 刪除後儲存
  }

  // ============================================
  // 訊息處理
  // ============================================

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _isLoading) return;

    _messageController.clear();

    // 如果當前沒有 session，建立一個新的
    if (_currentSession == null) {
      _createNewSession();
    }

    // 添加用戶訊息
    final userMessage = ChatMessage(content: message, isUser: true);
    if (!mounted) return;
    setState(() {
      _currentSession!.messages.add(userMessage);
      _currentSession!.updatedAt = DateTime.now();
      
      // 如果是第一條訊息，更新標題
      if (_currentSession!.messages.where((m) => m.isUser).length == 1) {
        _currentSession!.updateTitleFromFirstMessage();
      }
    });

    _scrollToBottom();

    // 添加 AI 回覆佔位符（顯示打字動畫）
    final aiPlaceholder = ChatMessage(
      content: '',
      isUser: false,
      isLoading: true,
    );
    if (!mounted) return;
    setState(() {
      _currentSession!.messages.add(aiPlaceholder);
      _isLoading = true;
    });

    _scrollToBottom();

    try {
      // 呼叫 AI API (注意參數順序: message, projectAreas, modelPreference, userId, sessionId)
      final response = await _aiService.getChatResponse(
        message,
        widget.selectedProjectAreas, // 使用 widget 傳入的區域
        _selectedModel,
        widget.userId,
        sessionId: _currentSession?.id, // 傳送 sessionId 以追蹤對話
      );

      // 更新 AI 回覆
      // [NEW] 解析圖表資料（兼容性 - 可選欄位）
      ChartData? chartData;
      if (response['chartData'] != null) {
        try {
          chartData = ChartData.fromJson(response['chartData'] as Map<String, dynamic>);
        } catch (e) {
          debugPrint('[AI Chat] 解析 chartData 失敗: $e');
        }
      }
      
      // [NEW] 解析智慧建議（兼容性 - 可選欄位）
      List<Map<String, dynamic>>? suggestions;
      if (response['suggestions'] != null) {
        try {
          suggestions = List<Map<String, dynamic>>.from(response['suggestions']);
        } catch (e) {
          debugPrint('[AI Chat] 解析 suggestions 失敗: $e');
        }
      }
      
      // [NEW] 解析異常警示（兼容性 - 可選欄位）
      List<Map<String, dynamic>>? anomalies;
      if (response['anomalies'] != null) {
        try {
          anomalies = List<Map<String, dynamic>>.from(response['anomalies']);
        } catch (e) {
          debugPrint('[AI Chat] 解析 anomalies 失敗: $e');
        }
      }
      
      if (mounted) {
        setState(() {
          final index = _currentSession!.messages.indexOf(aiPlaceholder);
          if (index != -1) {
            _currentSession!.messages[index] = aiPlaceholder.copyWith(
              content: response['response'] ?? response['answer'] ?? '抱歉，我無法處理這個請求。',
              isLoading: false,
              sources: response['sources'] != null
                  ? List<Map<String, dynamic>>.from(response['sources'])
                  : null,
              executedSQL: response['executedSQL'],
              chartData: chartData,
              suggestions: suggestions,
              anomalies: anomalies,
            );
          }
          _isLoading = false;
        });
      }
      
      // 每次訊息後自動儲存
      _saveSessions();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final index = _currentSession!.messages.indexOf(aiPlaceholder);
        if (index != -1) {
          _currentSession!.messages[index] = aiPlaceholder.copyWith(
            content: '發生錯誤：$e',
            isLoading: false,
            isError: true,
          );
        }
        _isLoading = false;
      });
    }

    _scrollToBottom();
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

  // ============================================
  // UI 構建
  // ============================================

  @override
  Widget build(BuildContext context) {
    final colorScheme = _isDarkMode ? _darkColorScheme : _lightColorScheme;

    return Theme(
      data: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
      ),
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: Row(
          children: [
            // 左側邊欄 - 對話歷史
            if (_isSidebarOpen) _buildSidebar(colorScheme),
            
            // 主聊天區域
            Expanded(
              child: Column(
                children: [
                  // 頂部工具列
                  _buildTopBar(colorScheme),
                  
                  // 聊天訊息區域
                  Expanded(
                    child: _buildChatArea(colorScheme),
                  ),
                  
                  // 底部輸入區域
                  _buildInputArea(colorScheme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 顏色配置 - 極簡現代風格
  ColorScheme get _lightColorScheme => ColorScheme.fromSeed(
        seedColor: const Color(0xFF10A37F), // 類似 ChatGPT 綠色
        brightness: Brightness.light,
      ).copyWith(
        surface: const Color(0xFFFAFAFA),
        surfaceContainerHighest: Colors.white,
        primary: const Color(0xFF10A37F),
        secondary: const Color(0xFF6B7280),
      );

  ColorScheme get _darkColorScheme => ColorScheme.fromSeed(
        seedColor: const Color(0xFF10A37F),
        brightness: Brightness.dark,
      ).copyWith(
        surface: const Color(0xFF0D0D0D),
        surfaceContainerHighest: const Color(0xFF1A1A1A),
        primary: const Color(0xFF10A37F),
        secondary: const Color(0xFF9CA3AF),
      );

  // ============================================
  // 側邊欄 - 現代化設計
  // ============================================

  Widget _buildSidebar(ColorScheme colorScheme) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      width: 280,
      decoration: BoxDecoration(
        color: _isDarkMode ? const Color(0xFF171717) : Colors.white,
        border: Border(
          right: BorderSide(
            color: colorScheme.outline.withOpacity(0.1),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // 頂部區域
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        colorScheme.primary,
                        colorScheme.primary.withOpacity(0.8),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.eco_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '對話記錄',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),

          // 新對話按鈕
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _createNewSession,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: colorScheme.outline.withOpacity(0.2),
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_rounded,
                        size: 20,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '新對話',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 16),

          // 對話歷史列表
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _sessions.length,
              itemBuilder: (context, index) {
                final session = _sessions[index];
                final isSelected = session == _currentSession;
                return _buildSessionTile(session, isSelected, colorScheme);
              },
            ),
          ),

          // 底部設定區域
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: colorScheme.outline.withOpacity(0.1),
                ),
              ),
            ),
            child: Column(
              children: [
                // 模型選擇
                _buildModelSelector(colorScheme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelSelector(ColorScheme colorScheme) {
    return PopupMenuButton<String>(
      initialValue: _selectedModel,
      onSelected: (value) => setState(() => _selectedModel = value),
      offset: const Offset(0, -200),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: colorScheme.outline.withOpacity(0.1),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.smart_toy_rounded,
              size: 18,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _availableModels[_selectedModel] ?? _selectedModel.split('/').last,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.unfold_more_rounded,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
      itemBuilder: (context) {
        final items = <PopupMenuEntry<String>>[];
        _modelCategories.forEach((category, data) {
          // 分類標題
          items.add(
            PopupMenuItem<String>(
              enabled: false,
              height: 32,
              child: Text(
                category,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
            ),
          );
          // 模型選項
          final models = Map<String, String>.from(data['models'] as Map);
          models.forEach((key, value) {
            items.add(
              PopupMenuItem<String>(
                value: key,
                height: 40,
                child: Row(
                  children: [
                    if (_selectedModel == key)
                      Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: colorScheme.primary,
                      )
                    else
                      const SizedBox(width: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        value,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          });
          items.add(const PopupMenuDivider(height: 8));
        });
        return items;
      },
    );
  }

  Widget _buildSessionTile(ChatSession session, bool isSelected, ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: isSelected 
            ? colorScheme.primary.withOpacity(0.12) 
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => _selectSession(session),
          onLongPress: () => _showDeleteConfirmation(session),
          borderRadius: BorderRadius.circular(10),
          hoverColor: colorScheme.primary.withOpacity(0.05),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isSelected 
                        ? colorScheme.primary.withOpacity(0.15)
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 16,
                    color: isSelected 
                        ? colorScheme.primary 
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatSessionDate(session.updatedAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                // 刪除按鈕（僅選中時顯示）
                if (isSelected)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _showDeleteConfirmation(session),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          size: 16,
                          color: colorScheme.error.withOpacity(0.7),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatSessionDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return '剛剛';
    if (diff.inHours < 1) return '${diff.inMinutes} 分鐘前';
    if (diff.inDays < 1) return '${diff.inHours} 小時前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return DateFormat('MM/dd').format(date);
  }

  void _showDeleteConfirmation(ChatSession session) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.delete_outline_rounded, color: Colors.red.shade400, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('刪除對話', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ],
        ),
        content: Text(
          '確定要刪除「${session.title}」嗎？\n此操作無法復原。',
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '取消',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteSession(session);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade400,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
  }

  // ============================================
  // 頂部工具列 - 極簡設計
  // ============================================

  Widget _buildTopBar(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outline.withOpacity(0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          // 側邊欄切換
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _isSidebarOpen = !_isSidebarOpen),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _isSidebarOpen 
                      ? colorScheme.primaryContainer.withOpacity(0.3)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _isSidebarOpen ? Icons.menu_open_rounded : Icons.menu_rounded,
                  color: colorScheme.onSurfaceVariant,
                  size: 22,
                ),
              ),
            ),
          ),
          
          const SizedBox(width: 12),
          
          // 新對話按鈕
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _createNewSession,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.edit_square,
                  color: colorScheme.onSurfaceVariant,
                  size: 20,
                ),
              ),
            ),
          ),
          
          const Spacer(),
          
          // 標題
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.eco_rounded,
                  size: 18,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '永續碳匯 AI',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          
          const Spacer(),

          // 深色模式切換
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _isDarkMode = !_isDarkMode),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  _isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                  color: colorScheme.onSurfaceVariant,
                  size: 20,
                ),
              ),
            ),
          ),
          
          const SizedBox(width: 8),

          // 返回按鈕
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => Navigator.of(context).pop(),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: colorScheme.outline.withOpacity(0.15),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.arrow_back_rounded,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '返回',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // 聊天區域
  // ============================================

  Widget _buildChatArea(ColorScheme colorScheme) {
    if (_currentSession == null || _currentSession!.messages.isEmpty) {
      return _buildEmptyState(colorScheme);
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      itemCount: _currentSession!.messages.length,
      itemBuilder: (context, index) {
        final message = _currentSession!.messages[index];
        return _buildMessageBubble(message, colorScheme);
      },
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _isDarkMode
              ? [const Color(0xFF0D0D0D), const Color(0xFF1A1A1A)]
              : [const Color(0xFFFAFAFA), Colors.white],
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo 動畫區域
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primary,
                      colorScheme.primary.withOpacity(0.7),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.eco_rounded,
                  size: 42,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 32),
              
              // 標題
              Text(
                '永續碳匯 AI',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),
              
              // 副標題
              Text(
                '智慧樹木管理與碳匯分析助手',
                style: TextStyle(
                  fontSize: 16,
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 48),
              
              // 功能說明卡片
              _buildFeatureCards(colorScheme),
              const SizedBox(height: 40),
              
              // 建議問題網格
              _buildSuggestionGrid(colorScheme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureCards(ColorScheme colorScheme) {
    final features = [
      {'icon': Icons.search_rounded, 'title': '智慧查詢', 'desc': '自然語言搜尋樹木資料'},
      {'icon': Icons.analytics_rounded, 'title': '數據分析', 'desc': '碳儲存量統計報表'},
      {'icon': Icons.lightbulb_rounded, 'title': '專業建議', 'desc': '樹木養護管理諮詢'},
    ];

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      alignment: WrapAlignment.center,
      children: features.map((f) => Container(
        width: 160,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.outline.withOpacity(0.1),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                f['icon'] as IconData,
                size: 24,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              f['title'] as String,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              f['desc'] as String,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      )).toList(),
    );
  }

  Widget _buildSuggestionGrid(ColorScheme colorScheme) {
    final suggestions = [
      '高雄港有多少棵樹？',
      '哪種樹碳儲存量最高？',
      '胸徑超過50公分的大樹',
      '統計各區位的樹木數量',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            '試試這些問題',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: suggestions.map((q) => _buildSuggestionChip(q, colorScheme)).toList(),
        ),
      ],
    );
  }

  Widget _buildSuggestionChip(String question, ColorScheme colorScheme) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          _messageController.text = question;
          _sendMessage();
        },
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: colorScheme.outline.withOpacity(0.2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.arrow_outward_rounded,
                size: 16,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                question,
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 保留舊的建議卡片方法用於可能的未來使用
  // ignore: unused_element
  Widget _buildSuggestionCardOld(
    IconData icon,
    String title,
    List<String> questions,
    ColorScheme colorScheme,
  ) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...questions.map((q) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () {
                _messageController.text = q;
                _sendMessage();
              },
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  q,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message, ColorScheme colorScheme) {
    final isUser = message.isUser;

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: EdgeInsets.symmetric(
        horizontal: MediaQuery.of(context).size.width > 800 
            ? MediaQuery.of(context).size.width * 0.1 
            : 0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 頭像
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: isUser
                  ? LinearGradient(
                      colors: [Colors.purple.shade400, Colors.purple.shade600],
                    )
                  : LinearGradient(
                      colors: [colorScheme.primary, colorScheme.primary.withOpacity(0.8)],
                    ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: (isUser ? Colors.purple : colorScheme.primary).withOpacity(0.2),
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
          ),
          const SizedBox(width: 16),

          // 訊息內容
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 發送者名稱
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    isUser ? '你' : '永續碳匯 AI',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                
                // 訊息內容
                if (message.isLoading)
                  _buildTypingIndicator(colorScheme)
                else
                  _buildMessageContent(message, isUser, colorScheme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (index) {
          return AnimatedBuilder(
            animation: _typingAnimationController,
            builder: (context, child) {
              final phase = (index / 3) * 2 * math.pi;
              final value = (math.sin(_typingAnimationController.value * 2 * math.pi + phase) + 1) / 2;
              return Container(
                margin: EdgeInsets.only(right: index < 2 ? 4 : 0),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.3 + value * 0.7),
                  shape: BoxShape.circle,
                ),
              );
            },
          );
        }),
      ),
    );
  }

  Widget _buildMessageContent(ChatMessage message, bool isUser, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Markdown 內容
        MarkdownBody(
          data: message.content,
          selectable: true,
          styleSheet: MarkdownStyleSheet(
            p: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 15,
              height: 1.7,
              letterSpacing: 0.1,
            ),
            h1: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
            h2: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
            h3: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
            code: TextStyle(
              backgroundColor: colorScheme.surfaceContainerHighest,
              color: colorScheme.primary,
              fontSize: 13,
              fontFamily: 'monospace',
            ),
            codeblockDecoration: BoxDecoration(
              color: _isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outline.withOpacity(0.1),
              ),
            ),
            codeblockPadding: const EdgeInsets.all(16),
            blockquoteDecoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: colorScheme.primary,
                  width: 4,
                ),
              ),
            ),
            blockquotePadding: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
            listBullet: TextStyle(color: colorScheme.onSurface),
            tableHead: TextStyle(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
            tableBorder: TableBorder.all(
              color: colorScheme.outline.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            tableCellsPadding: const EdgeInsets.all(12),
          ),
          onTapLink: (text, href, title) {
            if (href != null) {
              launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
            }
          },
        ),

        // 錯誤標記
        if (message.isError)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, size: 16, color: colorScheme.error),
                const SizedBox(width: 8),
                Text(
                  '回覆失敗，請重試',
                  style: TextStyle(fontSize: 13, color: colorScheme.error),
                ),
              ],
            ),
          ),

        // [NEW] 異常數據警示
        if (message.anomalies != null && message.anomalies!.isNotEmpty)
          _buildAnomaliesSection(message.anomalies!, colorScheme),

        // [NEW] 查詢結果圖表視覺化
        if (message.chartData != null && message.chartData!.data.isNotEmpty)
          _buildQueryChart(message.chartData!, colorScheme),

        // [NEW] 智慧建議
        if (message.suggestions != null && message.suggestions!.isNotEmpty)
          _buildSuggestionsSection(message.suggestions!, colorScheme),

        // SQL 查詢（可展開）
        if (message.executedSQL != null && message.executedSQL!.isNotEmpty)
          _buildExpandableSQL(message.executedSQL!, colorScheme),

        // 來源引用（可展開）
        if (message.sources != null && message.sources!.isNotEmpty)
          _buildSourcesSection(message.sources!, colorScheme),

        // 操作按鈕
        if (!isUser && !message.isLoading)
          Container(
            margin: const EdgeInsets.only(top: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildActionButton(
                  Icons.content_copy_rounded,
                  '複製',
                  () => _copyToClipboard(message.content),
                  colorScheme,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildActionButton(
    IconData icon,
    String tooltip,
    VoidCallback onPressed,
    ColorScheme colorScheme,
  ) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: colorScheme.outline.withOpacity(0.1),
              ),
            ),
            child: Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandableSQL(String sql, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.code, size: 14, color: colorScheme.primary),
              const SizedBox(width: 4),
              Text(
                '查看執行的 SQL',
                style: TextStyle(fontSize: 12, color: colorScheme.primary),
              ),
            ],
          ),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                sql,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourcesSection(List<Map<String, dynamic>> sources, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.source, size: 14, color: colorScheme.primary),
              const SizedBox(width: 4),
              Text(
                '${sources.length} 個資料來源',
                style: TextStyle(fontSize: 12, color: colorScheme.primary),
              ),
            ],
          ),
          children: sources.map((source) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '• ${source['title'] ?? source['original_source_title'] ?? '未知來源'}',
                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            SizedBox(width: 12),
            Text('已複製到剪貼簿'),
          ],
        ),
        backgroundColor: const Color(0xFF10A37F),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ============================================
  // 輸入區域 - 現代化設計
  // ============================================

  Widget _buildInputArea(ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outline.withOpacity(0.1),
          ),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: MediaQuery.of(context).size.width > 800 
                ? MediaQuery.of(context).size.width * 0.1 
                : 16,
            vertical: 16,
          ),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: colorScheme.outline.withOpacity(0.15),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // 輸入框
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    focusNode: _inputFocusNode,
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                    decoration: InputDecoration(
                      hintText: '輸入訊息，向 AI 助手提問...',
                      hintStyle: TextStyle(
                        color: colorScheme.onSurfaceVariant.withOpacity(0.6),
                        fontSize: 15,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                    ),
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                ),

                // 發送按鈕
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      gradient: _isLoading
                          ? null
                          : LinearGradient(
                              colors: [
                                colorScheme.primary,
                                colorScheme.primary.withOpacity(0.85),
                              ],
                            ),
                      color: _isLoading ? colorScheme.outline.withOpacity(0.3) : null,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: _isLoading
                          ? null
                          : [
                              BoxShadow(
                                color: colorScheme.primary.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _isLoading ? null : _sendMessage,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          child: _isLoading
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                )
                              : const Icon(
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
        ),
      ),
    );
  }

  // ============================================
  // [NEW] 查詢結果圖表視覺化
  // ============================================

  /// 建立查詢結果圖表 - 支援長條圖和圓餅圖
  Widget _buildQueryChart(ChartData chartData, ColorScheme colorScheme) {
    final bool isPie = chartData.type == 'pie';
    final List<Color> chartColors = [
      AppColors.forestGreen,
      AppColors.portBlue,
      AppColors.chartOrange,  // Fixed: warningOrange -> chartOrange
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.indigo,
      Colors.amber,
    ];

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isPie ? Icons.pie_chart_rounded : Icons.bar_chart_rounded,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '查詢結果視覺化',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: isPie ? 220 : 200,
            child: isPie
                ? _buildPieChart(chartData, chartColors, colorScheme)
                : _buildBarChart(chartData, chartColors, colorScheme),
          ),
          // 圓餅圖圖例
          if (isPie) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: List.generate(chartData.data.length, (index) {
                final item = chartData.data[index];
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: chartColors[index % chartColors.length],
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${item.label}: ${item.value.toStringAsFixed(1)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                );
              }),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPieChart(ChartData chartData, List<Color> colors, ColorScheme colorScheme) {
    final total = chartData.data.fold<double>(0, (sum, item) => sum + item.value);

    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 45,
        sections: List.generate(chartData.data.length, (index) {
          final item = chartData.data[index];
          final percentage = total > 0 ? (item.value / total * 100) : 0;
          return PieChartSectionData(
            color: colors[index % colors.length],
            value: item.value,
            title: percentage >= 5 ? '${percentage.toStringAsFixed(0)}%' : '',
            radius: 55,
            titleStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildBarChart(ChartData chartData, List<Color> colors, ColorScheme colorScheme) {
    final maxValue = chartData.data.fold<double>(
      0,
      (max, item) => item.value > max ? item.value : max,
    );

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxValue * 1.2,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final item = chartData.data[groupIndex];
              return BarTooltipItem(
                '${item.label}\n${item.value.toStringAsFixed(1)}',
                TextStyle(color: colorScheme.onSurface, fontSize: 12),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= 0 && value.toInt() < chartData.data.length) {
                  final label = chartData.data[value.toInt()].label;
                  final displayLabel = label.length > 6 ? '${label.substring(0, 5)}…' : label;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      displayLabel,
                      style: TextStyle(
                        fontSize: 10,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                return const Text('');
              },
              reservedSize: 30,
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 45,
              getTitlesWidget: (value, meta) {
                return Text(
                  value >= 1000
                      ? '${(value / 1000).toStringAsFixed(0)}k'
                      : value.toStringAsFixed(0),
                  style: TextStyle(
                    fontSize: 10,
                    color: colorScheme.onSurfaceVariant,
                  ),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxValue > 0 ? maxValue / 4 : 1,
          getDrawingHorizontalLine: (value) => FlLine(
            color: colorScheme.outline.withOpacity(0.1),
            strokeWidth: 1,
          ),
        ),
        barGroups: List.generate(chartData.data.length, (index) {
          final item = chartData.data[index];
          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: item.value,
                color: colors[index % colors.length],
                width: chartData.data.length > 8 ? 14 : 22,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
              ),
            ],
          );
        }),
      ),
    );
  }

  // ============================================
  // [NEW] 異常數據警示區塊
  // ============================================
  Widget _buildAnomaliesSection(List<Map<String, dynamic>> anomalies, ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, size: 18, color: Colors.orange),
              const SizedBox(width: 8),
              Text(
                '數據品質提醒',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...anomalies.map((anomaly) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  anomaly['icon'] ?? '⚠️',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    anomaly['message'] ?? '',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }

  // ============================================
  // [NEW] 智慧建議區塊
  // ============================================
  Widget _buildSuggestionsSection(List<Map<String, dynamic>> suggestions, ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline_rounded, size: 16, color: colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                '您可能還想問',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: suggestions.map((suggestion) {
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    final query = suggestion['query'] as String?;
                    if (query != null && query.isNotEmpty) {
                      _messageController.text = query;
                      _sendMessage();
                    }
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: colorScheme.primary.withOpacity(0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          suggestion['icon'] ?? '💡',
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            suggestion['text'] ?? '',
                            style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
