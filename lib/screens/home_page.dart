import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart'; // 引入 ApiService
import '../tree_survey_page.dart';
import '../tree_list_page.dart';
import 'cities_page.dart';
import '../main.dart'; // 引入 MyApp
import 'ble_import_page.dart'; // 引入 BleImportPage

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  String? _userName;

  @override
  void initState() {
    super.initState();
    // 觸發一次性的背景清理任務
    ApiService.triggerCleanup();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final userInfo = await AuthService.getUserInfo();
    if (mounted) {
      setState(() {
        _userName = userInfo?['display_name'] ?? userInfo?['username'];
      });
    }
  }

  final List<Widget> _widgetOptions = [
    const DashboardPage(),
    const TreeSurveyPage(),
    const TreeListPage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('歡迎，${_userName ?? '使用者'}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => AuthService.logout(context),
          ),
        ],
      ),
      body: _widgetOptions.elementAt(_selectedIndex),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: '首頁',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.folder),
            label: '專案',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.format_list_bulleted),
            label: '樹木列表',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.green,
        onTap: _onItemTapped,
      ),
    );
  }
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      padding: const EdgeInsets.all(20),
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      crossAxisCount: 2,
      children: [
        _buildDashboardItem(
          context,
          '樹木調查',
          Icons.nature,
          Colors.green,
          () => Navigator.pushNamed(context, '/tree-survey'),
        ),
        _buildDashboardItem(
          context,
          '數據統計',
          Icons.bar_chart,
          Colors.blue,
          () => Navigator.pushNamed(context, '/statistics'),
        ),
        _buildDashboardItem(
          context,
          '地圖檢視',
          Icons.map,
          Colors.orange,
          () => Navigator.pushNamed(context, '/map'),
        ),
        _buildDashboardItem(
          context,
          'AI助手',
          Icons.psychology,
          Colors.purple,
          () => Navigator.pushNamed(context, '/ai-assistant'),
        ),
        _buildDashboardItem(
          context,
          'AI永續分析',
          Icons.eco,
          Colors.teal,
          () => Navigator.pushNamed(context, '/ai-sustainability-report'),
        ),
        _buildDashboardItem(
          context,
          '縣市專案',
          Icons.location_city,
          Colors.indigo,
          () => Navigator.pushNamed(context, '/cities'),
        ),
        _buildDashboardItem(
          context,
          '儀器匯入',
          Icons.bluetooth_searching,
          Colors.deepOrange,
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const BleImportPage()),
          ),
        ),
      ],
    );
  }

  Widget _buildDashboardItem(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 48,
              color: color,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
