import 'package:flutter/material.dart';

class TreeLoadingIndicator extends StatefulWidget {
  final String message;
  final Stream<double>? progressStream;

  const TreeLoadingIndicator({
    Key? key,
    this.message = '載入中...',
    this.progressStream,
  }) : super(key: key);

  @override
  State<TreeLoadingIndicator> createState() => _TreeLoadingIndicatorState();
}

class _TreeLoadingIndicatorState extends State<TreeLoadingIndicator> {
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    if (widget.progressStream != null) {
      widget.progressStream!.listen((p) {
        setState(() {
          _progress = p;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.progressStream != null)
            LinearProgressIndicator(
              value: _progress,
              backgroundColor: Colors.grey[300],
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
            )
          else
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
            ),
          const SizedBox(height: 16),
          Text(
            widget.message,
            style: const TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
