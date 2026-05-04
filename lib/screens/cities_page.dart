import 'package:flutter/material.dart';
import '../constants/colors.dart';
import 'project_areas_page.dart';

class CitiesPage extends StatelessWidget {
  const CitiesPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 台灣縣市列表
    final List<Map<String, dynamic>> cities = [
      {'name': '臺北市', 'icon': Icons.location_city},
      {'name': '新北市', 'icon': Icons.location_city},
      {'name': '桃園市', 'icon': Icons.location_city},
      {'name': '臺中市', 'icon': Icons.location_city},
      {'name': '臺南市', 'icon': Icons.location_city},
      {'name': '高雄市', 'icon': Icons.location_city},
      {'name': '基隆市', 'icon': Icons.location_city},
      {'name': '新竹市', 'icon': Icons.location_city},
      {'name': '新竹縣', 'icon': Icons.landscape},
      {'name': '苗栗縣', 'icon': Icons.landscape},
      {'name': '彰化縣', 'icon': Icons.landscape},
      {'name': '南投縣', 'icon': Icons.landscape},
      {'name': '雲林縣', 'icon': Icons.landscape},
      {'name': '嘉義市', 'icon': Icons.location_city},
      {'name': '嘉義縣', 'icon': Icons.landscape},
      {'name': '屏東縣', 'icon': Icons.landscape},
      {'name': '宜蘭縣', 'icon': Icons.landscape},
      {'name': '花蓮縣', 'icon': Icons.landscape},
      {'name': '臺東縣', 'icon': Icons.landscape},
      {'name': '澎湖縣', 'icon': Icons.landscape},
      {'name': '金門縣', 'icon': Icons.landscape},
      {'name': '連江縣', 'icon': Icons.landscape},
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('選擇縣市'),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.forestGreen, AppColors.leafGreen],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        elevation: 4,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.surfaceLight, Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          children: [
            // 顯示全台灣選項
            Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.portBlueLight, AppColors.portBlue],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withValues(alpha:0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha:0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.public,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                title: const Text(
                  '全台灣',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: Colors.white,
                  ),
                ),
                subtitle: Text(
                  '查看所有區位',
                  style: TextStyle(color: Colors.white.withValues(alpha:0.9)),
                ),
                trailing: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha:0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.arrow_forward, color: Colors.white),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ProjectAreasPage(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 4),

            // 縣市列表
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: cities.length,
                itemBuilder: (context, index) {
                  final city = cities[index];
                  final bool isCity = city['name'].toString().endsWith('市');
                  final cityColor = isCity ? Colors.teal : Colors.green;

                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 5,
                    ),
                    elevation: 3,
                    shadowColor: cityColor.withValues(alpha:0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          colors: [Colors.white, cityColor.withValues(alpha:0.08)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        leading: Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [cityColor.shade400, cityColor.shade600],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            city['icon'],
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        title: Text(
                          city['name'],
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: cityColor.shade700,
                          ),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: cityColor.withValues(alpha:0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                            color: cityColor,
                          ),
                        ),
                        onTap: () {
                          // 傳完整縣市名（含「市/縣」），讓後端 normalizeCityCandidates 精準命中
                          // 不要砍尾綴，否則嘉義市/嘉義縣、新竹市/新竹縣會被合併成同一個查詢
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ProjectAreasPage(
                                cityName: city['name'],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
