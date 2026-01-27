import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// 服务状态卡片
class DesktopStatusCard extends StatelessWidget {
  final bool isRunning;
  final String localIp;
  final int tcpPort;

  const DesktopStatusCard({
    super.key,
    required this.isRunning,
    required this.localIp,
    required this.tcpPort,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = isRunning ? colorScheme.secondary : colorScheme.error;
    final statusText = isRunning ? '服务运行中' : '服务未启动';
    final statusIcon = isRunning
        ? PhosphorIconsRegular.checkCircle
        : PhosphorIconsRegular.warningCircle;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PhosphorIcon(statusIcon, color: statusColor, size: 20),
                const SizedBox(width: 10),
                Text(
                  statusText,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                _StatusPill(
                  label: isRunning ? '在线' : '离线',
                  color: statusColor,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(color: colorScheme.outlineVariant),
            const SizedBox(height: 8),
            _InfoRow(label: '本机 IP', value: localIp),
            _InfoRow(label: '发现端口 (UDP)', value: '9999'),
            _InfoRow(label: '通信端口 (TCP)', value: tcpPort.toString()),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  PhosphorIcon(
                    PhosphorIconsRegular.info,
                    size: 16,
                    color: colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '关闭窗口会最小化到托盘，右键托盘图标可退出',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          SelectableText(value),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
