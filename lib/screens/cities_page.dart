import 'package:flutter/material.dart';
import 'project_areas_page.dart';

class CitiesPage extends StatelessWidget {
  const CitiesPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 台灣縣市列表
    final List<Map<String, dynamic>> cities = [
      {'name': '台北市', 'icon': Icons.location_city},
      {'name': '新北市', 'icon': Icons.location_city},
      {'name': '桃園市', 'icon': Icons.location_city},
      {'name': '台中市', 'icon': Icons.location_city},
      {'name': '台南市', 'icon': Icons.location_city},
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
      {'name': '台東縣', 'icon': Icons.landscape},
      {'name': '澎湖縣', 'icon': Icons.landscape},
      {'name': '金門縣', 'icon': Icons.landscape},
      {'name': '連江縣', 'icon': Icons.landscape},
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('選擇縣市'),
      ),
      body: Column(
        children: [
          // 顯示全台灣選項
          ListTile(
            leading: const Icon(
              Icons.public,
              color: Colors.blue,
              size: 36,
            ),
            title: const Text(
              '全台灣',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            tileColor: Colors.blue.shade50,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ProjectAreasPage(),
                ),
              );
            },
          ),
          const Divider(thickness: 1),

          // 縣市列表
          Expanded(
            child: ListView.builder(
              itemCount: cities.length,
              itemBuilder: (context, index) {
                final city = cities[index];
                final bool isCity = city['name'].toString().endsWith('市');

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  elevation: 2,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isCity
                          ? Colors.green.shade600
                          : Colors.green.shade300,
                      child: Icon(
                        city['icon'],
                        color: Colors.white,
                      ),
                    ),
                    title: Text(
                      city['name'],
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                    ),
                    onTap: () {
                      // 從城市名稱中獲取縣市簡稱，如"台北市"變成"台北"
                      final String simpleName = city['name']
                          .toString()
                          .replaceAll('市', '')
                          .replaceAll('縣', '');

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ProjectAreasPage(
                            cityName: simpleName,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
