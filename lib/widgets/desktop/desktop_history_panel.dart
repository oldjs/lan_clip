import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../models/received_message.dart';

/// 接收历史面板
class DesktopHistoryPanel extends StatelessWidget {
  final bool showHistory;
  final List<ReceivedMessage> messages;
  final VoidCallback onClear;
  final ValueChanged<bool> onToggle;
  final ValueChanged<ReceivedMessage> onCopy;
  final ValueChanged<ReceivedMessage> onOpen;

  const DesktopHistoryPanel({
    super.key,
    required this.showHistory,
    required this.messages,
    required this.onClear,
    required this.onToggle,
    required this.onCopy,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                PhosphorIcon(
                  PhosphorIconsRegular.clockCounterClockwise,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  '接收历史',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            Row(
              children: [
                if (messages.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => _confirmClear(context),
                    icon: PhosphorIcon(
                      PhosphorIconsRegular.trashSimple,
                      size: 16,
                    ),
                    label: const Text('清空'),
                  ),
                Text(
                  showHistory ? '显示' : '隐藏',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                Switch(
                  value: showHistory,
                  onChanged: onToggle,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (showHistory)
          Expanded(
            child: Card(
              child: messages.isEmpty
                  ? Center(
                      child: Text(
                        '暂无记录',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: messages.length,
                      separatorBuilder: (_, _) => Divider(
                        color: colorScheme.outlineVariant,
                        height: 1,
                      ),
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        return ListTile(
                          title: Text(
                            message.content,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(_formatTime(message.time)),
                          trailing: IconButton(
                            icon: PhosphorIcon(
                              PhosphorIconsRegular.copy,
                              size: 18,
                            ),
                            onPressed: () => onCopy(message),
                          ),
                          onTap: () => onOpen(message),
                        );
                      },
                    ),
            ),
          ),
      ],
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空历史'),
        content: const Text('确定要清空所有接收历史吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      onClear();
    }
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }
}
