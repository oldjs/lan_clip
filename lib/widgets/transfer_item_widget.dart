import 'package:flutter/material.dart';
import '../models/file_transfer.dart';

/// 文件传输项组件
/// 显示单个传输任务的进度、状态和操作按钮
class TransferItemWidget extends StatefulWidget {
  final FileTransferTask task;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onCancel;
  final VoidCallback? onRemove;
  final VoidCallback? onOpen;

  const TransferItemWidget({
    super.key,
    required this.task,
    this.onPause,
    this.onResume,
    this.onCancel,
    this.onRemove,
    this.onOpen,
  });

  @override
  State<TransferItemWidget> createState() => _TransferItemWidgetState();
}

class _TransferItemWidgetState extends State<TransferItemWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 顶部: 文件名和状态
                Row(
                  children: [
                    _buildFileIcon(),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.task.fileName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              _buildDirectionBadge(),
                              const SizedBox(width: 8),
                              Text(
                                widget.task.formattedSize,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const Spacer(),
                              _buildStatusBadge(),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                // 进度条区域
                if (widget.task.isActive || 
                    widget.task.status == TransferStatus.completed) ...[
                  const SizedBox(height: 12),
                  _buildProgressSection(),
                ],
                
                // 底部操作栏
                const SizedBox(height: 8),
                _buildActionBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 文件图标
  Widget _buildFileIcon() {
    IconData icon;
    Color color;
    
    final ext = widget.task.fileName.split('.').last.toLowerCase();
    
    // 根据扩展名选择图标
    if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext)) {
      icon = Icons.image;
      color = Colors.green;
    } else if (['mp4', 'avi', 'mov', 'mkv', 'wmv'].contains(ext)) {
      icon = Icons.video_file;
      color = Colors.purple;
    } else if (['mp3', 'wav', 'flac', 'aac', 'ogg'].contains(ext)) {
      icon = Icons.audio_file;
      color = Colors.orange;
    } else if (['pdf'].contains(ext)) {
      icon = Icons.picture_as_pdf;
      color = Colors.red;
    } else if (['doc', 'docx', 'txt', 'rtf'].contains(ext)) {
      icon = Icons.description;
      color = Colors.blue;
    } else if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) {
      icon = Icons.folder_zip;
      color = Colors.amber;
    } else if (['apk'].contains(ext)) {
      icon = Icons.android;
      color = Colors.green.shade700;
    } else {
      icon = Icons.insert_drive_file;
      color = Colors.grey;
    }
    
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: 28),
    );
  }

  /// 传输方向标签
  Widget _buildDirectionBadge() {
    final isSend = widget.task.direction == TransferDirection.send;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isSend ? Colors.blue.shade50 : Colors.green.shade50,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSend ? Icons.upload : Icons.download,
            size: 12,
            color: isSend ? Colors.blue : Colors.green,
          ),
          const SizedBox(width: 2),
          Text(
            isSend ? '发送' : '接收',
            style: TextStyle(
              fontSize: 10,
              color: isSend ? Colors.blue : Colors.green,
            ),
          ),
        ],
      ),
    );
  }

  /// 状态标签
  Widget _buildStatusBadge() {
    String text;
    Color color;
    IconData icon;
    
    switch (widget.task.status) {
      case TransferStatus.pending:
        text = '等待中';
        color = Colors.grey;
        icon = Icons.hourglass_empty;
        break;
      case TransferStatus.connecting:
        text = '连接中';
        color = Colors.blue;
        icon = Icons.sync;
        break;
      case TransferStatus.transferring:
        text = '传输中';
        color = Colors.blue;
        icon = Icons.swap_horiz;
        break;
      case TransferStatus.paused:
        text = '已暂停';
        color = Colors.orange;
        icon = Icons.pause;
        break;
      case TransferStatus.completed:
        text = '已完成';
        color = Colors.green;
        icon = Icons.check_circle;
        break;
      case TransferStatus.failed:
        text = '失败';
        color = Colors.red;
        icon = Icons.error;
        break;
      case TransferStatus.cancelled:
        text = '已取消';
        color = Colors.grey;
        icon = Icons.cancel;
        break;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// 进度区域
  Widget _buildProgressSection() {
    return Column(
      children: [
        // 进度条
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            tween: Tween<double>(
              begin: 0,
              end: widget.task.progress,
            ),
            builder: (context, value, child) {
              return LinearProgressIndicator(
                value: value,
                minHeight: 6,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  _getProgressColor(),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        
        // 进度详情
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${widget.task.formattedTransferred} / ${widget.task.formattedSize}',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
            ),
            Text(
              '${(widget.task.progress * 100).toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        
        // 速度和剩余时间(仅传输中显示)
        if (widget.task.status == TransferStatus.transferring) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.speed, size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text(
                    widget.task.formattedSpeed,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Icon(Icons.timer, size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text(
                    '剩余 ${widget.task.formattedRemainingTime}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// 获取进度条颜色
  Color _getProgressColor() {
    switch (widget.task.status) {
      case TransferStatus.completed:
        return Colors.green;
      case TransferStatus.failed:
        return Colors.red;
      case TransferStatus.paused:
        return Colors.orange;
      case TransferStatus.cancelled:
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }

  /// 操作栏
  Widget _buildActionBar() {
    final actions = <Widget>[];
    
    // 暂停/恢复按钮
    if (widget.task.canPause) {
      actions.add(
        _buildActionButton(
          icon: Icons.pause,
          label: '暂停',
          onTap: widget.onPause,
          color: Colors.orange,
        ),
      );
    } else if (widget.task.canResume) {
      final isFailed = widget.task.status == TransferStatus.failed;
      actions.add(
        _buildActionButton(
          icon: isFailed ? Icons.refresh : Icons.play_arrow,
          label: isFailed ? '重试' : '继续',
          onTap: widget.onResume,
          color: Colors.green,
        ),
      );
    }
    
    // 取消按钮
    if (widget.task.canCancel) {
      actions.add(
        _buildActionButton(
          icon: Icons.close,
          label: '取消',
          onTap: widget.onCancel,
          color: Colors.red,
        ),
      );
    }
    
    // 完成后的操作
    if (widget.task.status == TransferStatus.completed) {
      // 打开文件
      if (widget.task.direction == TransferDirection.receive) {
        actions.add(
          _buildActionButton(
            icon: Icons.open_in_new,
            label: '打开',
            onTap: widget.onOpen,
            color: Colors.blue,
          ),
        );
      }
    }
    
    // 删除按钮(非活跃状态)
    if (!widget.task.isActive) {
      actions.add(
        _buildActionButton(
          icon: Icons.delete_outline,
          label: '删除',
          onTap: widget.onRemove,
          color: Colors.grey,
        ),
      );
    }
    
    // 错误信息
    if (widget.task.status == TransferStatus.failed && 
        widget.task.error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 14, color: Colors.red.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.task.error!,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.red.shade700,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: actions,
          ),
        ],
      );
    }
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: actions,
    );
  }

  /// 操作按钮
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 空状态组件
class EmptyTransferWidget extends StatelessWidget {
  const EmptyTransferWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.swap_horiz,
            size: 64,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            '暂无传输任务',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击右下角按钮选择文件发送',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }
}
