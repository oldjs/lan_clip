import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// 桌面端顶部栏
class DesktopAppBar extends StatelessWidget implements PreferredSizeWidget {
  final int activeTransferCount;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenTransfer;
  final VoidCallback? onLockPhone;
  final VoidCallback? onMinimize;

  const DesktopAppBar({
    super.key,
    required this.activeTransferCount,
    required this.onOpenSettings,
    required this.onOpenTransfer,
    this.onLockPhone,
    this.onMinimize,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppBar(
      titleSpacing: 20,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LAN Clip',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            '桌面接收端',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        _AppBarIconButton(
          tooltip: '设置',
          icon: PhosphorIconsRegular.gearSix,
          onPressed: onOpenSettings,
        ),
        const SizedBox(width: 4),
        if (onLockPhone != null) ...[
          _AppBarIconButton(
            tooltip: '手机锁屏',
            icon: PhosphorIconsRegular.lockSimple,
            onPressed: onLockPhone!,
          ),
          const SizedBox(width: 4),
        ],
        _AppBarIconButton(
          tooltip: '文件传输',
          icon: PhosphorIconsRegular.folderOpen,
          onPressed: onOpenTransfer,
          badgeCount: activeTransferCount,
        ),
        if (onMinimize != null) ...[
          const SizedBox(width: 4),
          _AppBarIconButton(
            tooltip: '最小化到托盘',
            icon: PhosphorIconsRegular.minus,
            onPressed: onMinimize!,
          ),
        ],
        const SizedBox(width: 12),
      ],
    );
  }
}

/// 顶部栏图标按钮
class _AppBarIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final int badgeCount;

  const _AppBarIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            PhosphorIcon(icon, size: 22),
            if (badgeCount > 0)
              Positioned(
                right: -6,
                top: -6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.tertiary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(minWidth: 18),
                  child: Text(
                    badgeCount.toString(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onTertiary,
                      fontSize: 10,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
