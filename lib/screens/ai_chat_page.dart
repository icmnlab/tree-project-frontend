import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';

import '../services/ai_service.dart';

/// 現代化 AI 聊天頁面
/// 設計參考: ChatGPT, Claude, Gemini
/// 
/// 功能:
/// - 純對話介面（移除樹種比較、碳足跡計算等 Tab）
/// - 對話歷史列表（左側可收合）
/// - 打字動畫效果
/// - Markdown 渲染
/// - 深色/淺色主題

// ============================================
// 資料模型
// ============================================

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

  ChatMessage({
    String? id,
    required this.content,
    required this.isUser,
    DateTime? timestamp,
    this.isLoading = false,
    this.isError = false,
    this.sources,
    this.executedSQL,
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        timestamp = timestamp ?? DateTime.now();

  ChatMessage copyWith({
    String? content,
    bool? isLoading,
    bool? isError,
    List<Map<String, dynamic>>? sources,
    String? executedSQL,
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
  bool _isSidebarOpen = true;
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
          );
        }
        _isLoading = false;
      });
      
      // 每次訊息後自動儲存
      _saveSessions();
    } catch (e) {
      // 處理錯誤
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

  // 顏色配置
  ColorScheme get _lightColorScheme => ColorScheme.fromSeed(
        seedColor: Colors.green,
        brightness: Brightness.light,
      ).copyWith(
        surface: const Color(0xFFF7F7F8),
        surfaceContainerHighest: Colors.white,
      );

  ColorScheme get _darkColorScheme => ColorScheme.fromSeed(
        seedColor: Colors.green,
        brightness: Brightness.dark,
      ).copyWith(
        surface: const Color(0xFF171717),
        surfaceContainerHighest: const Color(0xFF212121),
      );

  // ============================================
  // 側邊欄
  // ============================================

  Widget _buildSidebar(ColorScheme colorScheme) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 260,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(
          right: BorderSide(
            color: colorScheme.outlineVariant.withOpacity(0.3),
          ),
        ),
      ),
      child: Column(
        children: [
          // 新對話按鈕
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _createNewSession,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新對話'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(color: colorScheme.outline.withOpacity(0.3)),
                ),
              ),
            ),
          ),

          const Divider(height: 1),

          // 對話歷史列表
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _sessions.length,
              itemBuilder: (context, index) {
                final session = _sessions[index];
                final isSelected = session == _currentSession;

                return _buildSessionTile(session, isSelected, colorScheme);
              },
            ),
          ),

          const Divider(height: 1),

          // 底部設定區域
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // 模型選擇（分類顯示）
                Expanded(
                  child: PopupMenuButton<String>(
                    initialValue: _selectedModel,
                    onSelected: (value) {
                      setState(() => _selectedModel = value);
                    },
                    itemBuilder: (context) {
                      final items = <PopupMenuEntry<String>>[];
                      _modelCategories.forEach((category, data) {
                        // 分類標題
                        items.add(PopupMenuItem<String>(
                          enabled: false,
                          height: 32,
                          child: Text(
                            category,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                        ));
                        // 該分類的模型
                        final models = data['models'] as Map<String, dynamic>;
                        models.forEach((key, value) {
                          items.add(PopupMenuItem<String>(
                            value: key,
                            height: 36,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 12),
                              child: Row(
                                children: [
                                  if (key == _selectedModel)
                                    Icon(Icons.check, size: 14, color: colorScheme.primary)
                                  else
                                    const SizedBox(width: 14),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      value.toString(),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: key == _selectedModel ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ));
                        });
                        items.add(const PopupMenuDivider());
                      });
                      if (items.isNotEmpty) items.removeLast(); // 移除最後的分隔線
                      return items;
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: colorScheme.surface,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome, size: 16, color: colorScheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _availableModels[_selectedModel]?.split(' ').first ?? 'AI',
                              style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(Icons.expand_more, size: 16, color: colorScheme.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 主題切換
                IconButton(
                  onPressed: () {
                    setState(() => _isDarkMode = !_isDarkMode);
                  },
                  icon: Icon(
                    _isDarkMode ? Icons.light_mode : Icons.dark_mode,
                    size: 20,
                  ),
                  tooltip: _isDarkMode ? '切換淺色模式' : '切換深色模式',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionTile(ChatSession session, bool isSelected, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: isSelected 
            ? colorScheme.primary.withOpacity(0.1) 
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => _selectSession(session),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 16,
                  color: isSelected 
                      ? colorScheme.primary 
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          color: colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatSessionDate(session.updatedAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // 刪除按鈕
                if (isSelected)
                  IconButton(
                    onPressed: () => _showDeleteConfirmation(session),
                    icon: Icon(
                      Icons.delete_outline,
                      size: 16,
                      color: colorScheme.error,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
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
        title: const Text('刪除對話'),
        content: Text('確定要刪除「${session.title}」嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteSession(session);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
  }

  // ============================================
  // 頂部工具列
  // ============================================

  Widget _buildTopBar(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withOpacity(0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          // 側邊欄切換
          IconButton(
            onPressed: () {
              setState(() => _isSidebarOpen = !_isSidebarOpen);
            },
            icon: Icon(
              _isSidebarOpen ? Icons.menu_open : Icons.menu,
              color: colorScheme.onSurfaceVariant,
            ),
            tooltip: _isSidebarOpen ? '收合側邊欄' : '展開側邊欄',
          ),
          
          const SizedBox(width: 8),
          
          // 標題
          Text(
            '🌳 永續碳匯 AI 助手',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          
          const Spacer(),

          // 返回按鈕
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('返回'),
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.eco,
            size: 64,
            color: colorScheme.primary.withOpacity(0.5),
          ),
          const SizedBox(height: 24),
          Text(
            '永續碳匯 AI 助手',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '我可以幫助你查詢樹木資料、分析碳匯數據',
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          // 建議問題 - 分類展示
          _buildSuggestionGrid(colorScheme),
        ],
      ),
    );
  }

  Widget _buildSuggestionGrid(ColorScheme colorScheme) {
    final suggestions = [
      {
        'icon': Icons.pin_drop,
        'title': '區位查詢',
        'questions': [
          '高雄港有多少棵樹？',
          '花蓮港有哪些樹種？',
          '統計各區位的樹木數量',
        ],
      },
      {
        'icon': Icons.eco,
        'title': '樹種分析',
        'questions': [
          '榕樹的平均胸徑是多少？',
          '哪種樹碳儲存量最高？',
          '列出所有樟樹的資料',
        ],
      },
      {
        'icon': Icons.analytics,
        'title': '數據統計',
        'questions': [
          '胸徑超過50公分的大樹有哪些？',
          '碳儲存量前10名的樹木',
          '所有樹木的總碳儲存量',
        ],
      },
      {
        'icon': Icons.search,
        'title': '精確搜尋',
        'questions': [
          '查詢編號 7 的樹木',
          '找出需要關注的樹木',
          '2022年調查的樹有幾棵？',
        ],
      },
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        alignment: WrapAlignment.center,
        children: suggestions.map((category) {
          return _buildSuggestionCard(
            category['icon'] as IconData,
            category['title'] as String,
            category['questions'] as List<String>,
            colorScheme,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSuggestionCard(
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AI 頭像
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: colorScheme.primary,
              child: const Icon(Icons.eco, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 12),
          ],

          // 訊息內容
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.7,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser
                    ? colorScheme.primary
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: message.isLoading
                  ? _buildTypingIndicator(colorScheme)
                  : _buildMessageContent(message, isUser, colorScheme),
            ),
          ),

          // 用戶頭像
          if (isUser) ...[
            const SizedBox(width: 12),
            CircleAvatar(
              radius: 16,
              backgroundColor: colorScheme.tertiary,
              child: const Icon(Icons.person, size: 18, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(ColorScheme colorScheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _typingAnimationController,
          builder: (context, child) {
            final value = (_typingAnimationController.value + index * 0.2) % 1.0;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
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
              color: isUser ? Colors.white : colorScheme.onSurface,
              fontSize: 14,
              height: 1.5,
            ),
            code: TextStyle(
              backgroundColor: isUser
                  ? Colors.white.withOpacity(0.2)
                  : colorScheme.surface,
              color: isUser ? Colors.white : colorScheme.primary,
              fontSize: 13,
            ),
            codeblockDecoration: BoxDecoration(
              color: isUser
                  ? Colors.white.withOpacity(0.1)
                  : colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onTapLink: (text, href, title) {
            if (href != null) {
              launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
            }
          },
        ),

        // 錯誤標記
        if (message.isError)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 14, color: colorScheme.error),
                const SizedBox(width: 4),
                Text(
                  '回覆失敗',
                  style: TextStyle(fontSize: 12, color: colorScheme.error),
                ),
              ],
            ),
          ),

        // SQL 查詢（可展開）
        if (message.executedSQL != null && message.executedSQL!.isNotEmpty)
          _buildExpandableSQL(message.executedSQL!, colorScheme),

        // 來源引用（可展開）
        if (message.sources != null && message.sources!.isNotEmpty)
          _buildSourcesSection(message.sources!, colorScheme),

        // 操作按鈕
        if (!isUser && !message.isLoading)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildActionIcon(
                  Icons.copy,
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

  Widget _buildActionIcon(
    IconData icon,
    String tooltip,
    VoidCallback onPressed,
    ColorScheme colorScheme,
  ) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已複製到剪貼簿'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  // ============================================
  // 輸入區域
  // ============================================

  Widget _buildInputArea(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withOpacity(0.3),
          ),
        ),
      ),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 輸入框
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 150),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: colorScheme.outline.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        focusNode: _inputFocusNode,
                        maxLines: null,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        decoration: InputDecoration(
                          hintText: '輸入訊息...',
                          hintStyle: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 8),

            // 發送按鈕
            Container(
              decoration: BoxDecoration(
                color: _isLoading
                    ? colorScheme.outline
                    : colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                onPressed: _isLoading ? null : _sendMessage,
                icon: _isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.onPrimary,
                        ),
                      )
                    : Icon(
                        Icons.arrow_upward,
                        color: colorScheme.onPrimary,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
