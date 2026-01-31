import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// 服务状态卡片（可折叠）
class DesktopStatusCard extends StatefulWidget {
  final bool isRunning;
  final String localIp;
  final int tcpPort;
  final int connectedDeviceCount;
  final VoidCallback? onShowQR;

  const DesktopStatusCard({
    super.key,
    required this.isRunning,
    required this.localIp,
    required this.tcpPort,
    this.connectedDeviceCount = 0,
    this.onShowQR,
  });

  @override
  State<DesktopStatusCard> createState() => _DesktopStatusCardState();
}

class _DesktopStatusCardState extends State<DesktopStatusCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = widget.isRunning ? colorScheme.secondary : colorScheme.error;
    final statusText = widget.isRunning ? '服务运行中' : '服务未启动';
    final statusIcon = widget.isRunning
        ? PhosphorIconsRegular.checkCircle
        : PhosphorIconsRegular.warningCircle;

    return Card(
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  PhosphorIcon(statusIcon, color: statusColor, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    statusText,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(width: 8),
                  if (widget.connectedDeviceCount > 0)
                    Text(
                      '· ${widget.connectedDeviceCount} 台设备',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  const Spacer(),
                  _StatusPill(
                    label: widget.isRunning ? '在线' : '离线',
                    color: statusColor,
                  ),
                  const SizedBox(width: 8),
                  PhosphorIcon(
                    _expanded ? PhosphorIconsRegular.caretUp : PhosphorIconsRegular.caretDown,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    Divider(color: colorScheme.outlineVariant),
                    const SizedBox(height: 8),
                    _InfoRow(label: '本机 IP', value: widget.localIp),
                    _InfoRow(label: '发现端口 (UDP)', value: '9999'),
                    _InfoRow(label: '通信端口 (TCP)', value: widget.tcpPort.toString()),
                    _InfoRow(
                      label: '已连接设备',
                      value: widget.connectedDeviceCount > 0
                          ? '${widget.connectedDeviceCount} 台'
                          : '无',
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: widget.onShowQR,
                            icon: const Icon(Icons.qr_code),
                            label: const Text('扫码连接'),
                          ),
                        ),
                      ],
                    ),
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
                crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 200),
              ),
            ],
          ),
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
          SelectableText(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
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
