import 'package:flutter/material.dart';
import '../tree_input_page.dart';
import '../tree_input_page_v2.dart';

class AddTreeSelectionDialog extends StatelessWidget {
  final Map<String, dynamic> initialData;
  final Function() onDataChanged;

  const AddTreeSelectionDialog({
    super.key,
    this.initialData = const {},
    required this.onDataChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('選擇新增模式'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.article, color: Colors.green),
            title: const Text('標準模式 (V1)'),
            subtitle: const Text('傳統輸入介面，前端生成編號'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TreeInputPage(treeData: initialData),
                ),
              ).then((_) => onDataChanged());
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.flash_on, color: Colors.teal),
            title: const Text('快速模式 (V2 Beta)'),
            subtitle: const Text('優化輸入體驗，後端生成編號'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TreeInputPageV2(treeData: initialData),
                ),
              ).then((_) => onDataChanged());
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }

  static void show(
    BuildContext context, {
    Map<String, dynamic> initialData = const {},
    required Function() onDataChanged,
  }) {
    showDialog(
      context: context,
      builder: (context) => AddTreeSelectionDialog(
        initialData: initialData,
        onDataChanged: onDataChanged,
      ),
    );
  }
}
