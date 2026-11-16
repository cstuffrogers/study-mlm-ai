// 跨设备续学提示 + 离线暂存提示（T052）
import 'package:flutter/material.dart';

class SyncNotice extends StatelessWidget {
  final String message;
  final bool offline;
  final VoidCallback? onRetry;

  const SyncNotice({super.key, required this.message, this.offline = false, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final color = offline ? const Color(0xFFB45309) : const Color(0xFFC8161D);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: color.withValues(alpha: 0.1),
      child: Row(
        children: [
          Icon(offline ? Icons.cloud_off : Icons.cloud_sync, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: TextStyle(fontSize: 12, color: color))),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('重试', style: TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}
