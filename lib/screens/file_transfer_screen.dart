import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import '../models/file_transfer.dart';
import '../models/device.dart';
import '../services/file_transfer_service.dart';
import '../services/auth_service.dart';
import '../services/encryption_service.dart';
import '../widgets/transfer_item_widget.dart';

/// 文件传输页面
/// 显示传输列表，支持发送文件
class FileTransferScreen extends StatefulWidget {
  final Device? selectedDevice;
  final String? passwordHash;

  const FileTransferScreen({
    super.key,
    this.selectedDevice,
    this.passwordHash,
  });

  @override
  State<FileTransferScreen> createState() => _FileTransferScreenState();
}

class _FileTransferScreenState extends State<FileTransferScreen>
    with SingleTickerProviderStateMixin {
  final _transferService = FileTransferService();
  late TabController _tabController;
  
  List<FileTransferTask> _allTasks = [];
  StreamSubscription<List<FileTransferTask>>? _taskSubscription;
  String _downloadPath = '';
  bool _autoAccept = false;
  bool _encryptionEnabled = false;
  bool _passwordEnabled = false;
  
  // 过滤后的任务列表
  List<FileTransferTask> get _sendingTasks => 
      _allTasks.where((t) => t.direction == TransferDirection.send).toList();
  List<FileTransferTask> get _receivingTasks => 
      _allTasks.where((t) => t.direction == TransferDirection.receive).toList();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initService();
    _loadLocalInfo();
  }

  Future<void> _initService() async {
    // 启动服务(如果还没启动)
    try {
      await _transferService.startServer();
    } catch (e) {
      // 启动失败时提示用户
      if (mounted) {
        _showSnackBar('文件传输服务启动失败: $e');
      }
    }
    
    // 监听任务变化
    _taskSubscription = _transferService.taskStream.listen((tasks) {
      setState(() => _allTasks = tasks);
    });
    
    // 初始化任务列表
    setState(() => _allTasks = _transferService.tasks);
  }

  Future<void> _loadLocalInfo() async {
    final downloadPath = await _transferService.getDownloadPath();
    final autoAccept = await _transferService.isAutoAcceptEnabled();
    final encryptionEnabled = await EncryptionService.isEncryptionEnabled();
    final passwordEnabled = await AuthService.isPasswordEnabled();

    if (mounted) {
      setState(() {
        _downloadPath = downloadPath;
        _autoAccept = autoAccept;
        _encryptionEnabled = encryptionEnabled;
        _passwordEnabled = passwordEnabled;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _taskSubscription?.cancel();
    super.dispose();
  }

  /// 选择并发送文件
  Future<void> _pickAndSendFiles() async {
    if (widget.selectedDevice == null) {
      _showSnackBar('请先连接设备');
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
    );

    if (result != null && result.files.isNotEmpty) {
      final paths = result.files
          .where((f) => f.path != null)
          .map((f) => f.path!)
          .toList();

      if (paths.isEmpty) {
        _showSnackBar('无法读取选中的文件');
        return;
      }

      // 显示确认对话框
      final confirmed = await _showSendConfirmDialog(paths);
      if (confirmed == true) {
        await _transferService.sendFiles(
          filePaths: paths,
          device: widget.selectedDevice!,
          passwordHash: widget.passwordHash,
        );
        _showSnackBar('开始传输 ${paths.length} 个文件');
      }
    }
  }

  /// 显示发送确认对话框
  Future<bool?> _showSendConfirmDialog(List<String> paths) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认发送'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '将发送 ${paths.length} 个文件到 ${widget.selectedDevice?.name}:',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: paths.length,
                  itemBuilder: (context, index) {
                    final fileName = paths[index].split(Platform.pathSeparator).last;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(Icons.insert_drive_file, 
                               size: 16, color: Colors.grey.shade600),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              fileName,
                              style: const TextStyle(fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('发送'),
          ),
        ],
      ),
    );
  }

  /// 打开文件
  Future<void> _openFile(FileTransferTask task) async {
    final result = await OpenFilex.open(task.localPath);
    if (result.type != ResultType.done) {
      _showSnackBar('无法打开文件: ${result.message}');
    }
  }

  /// 打开下载目录
  Future<void> _openDownloadFolder() async {
    final path = await _transferService.getDownloadPath();
    if (Platform.isWindows) {
      await Process.run('explorer', [path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [path]);
    } else {
      // Android/iOS - 打开文件管理器
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done) {
        _showSnackBar('下载目录: $path');
      }
    }
  }

  /// 修改下载目录(仅桌面端)
  Future<void> _pickDownloadFolder() async {
    if (Platform.isAndroid || Platform.isIOS) {
      _showSnackBar('移动端暂不支持修改目录');
      return;
    }

    final selected = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择保存位置',
      initialDirectory: _downloadPath,
    );
    if (selected == null) return;

    await _transferService.setDownloadPath(selected);
    if (mounted) {
      setState(() => _downloadPath = selected);
    }
  }

  /// 切换自动接收
  Future<void> _toggleAutoAccept(bool value) async {
    await _transferService.setAutoAcceptEnabled(value);
    if (mounted) {
      setState(() => _autoAccept = value);
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  /// 顶部信息面板
  Widget _buildInfoPanel() {
    final pathText = _downloadPath.isEmpty ? '加载中...' : _downloadPath;
    final canEditPath = !(Platform.isAndroid || Platform.isIOS);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            // 下载目录
            Row(
              children: [
                const Icon(Icons.folder_open, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    pathText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 18),
                  tooltip: '修改目录',
                  onPressed: canEditPath ? _pickDownloadFolder : null,
                ),
                IconButton(
                  icon: const Icon(Icons.open_in_new, size: 18),
                  tooltip: '打开目录',
                  onPressed: _openDownloadFolder,
                ),
              ],
            ),
            const Divider(height: 1),
            const SizedBox(height: 4),
            // 安全状态
            Row(
              children: [
                const Icon(Icons.shield, size: 18),
                const SizedBox(width: 8),
                const Text('安全', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 8),
                _buildStatusChip('加密', _encryptionEnabled),
                const SizedBox(width: 6),
                _buildStatusChip('密码', _passwordEnabled),
              ],
            ),
            const SizedBox(height: 4),
            // 自动接收
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('始终自动接收', style: TextStyle(fontSize: 12)),
              value: _autoAccept,
              onChanged: _toggleAutoAccept,
            ),
          ],
        ),
      ),
    );
  }

  /// 状态标签
  Widget _buildStatusChip(String label, bool enabled) {
    final color = enabled ? Colors.green : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$label${enabled ? '已开' : '已关'}',
        style: TextStyle(fontSize: 11, color: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('文件传输'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // 打开下载目录
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: '打开下载目录',
            onPressed: _openDownloadFolder,
          ),
          // 清空已完成
          if (_allTasks.any((t) => !t.isActive))
            IconButton(
              icon: const Icon(Icons.cleaning_services),
              tooltip: '清空已完成',
              onPressed: () {
                _transferService.clearCompletedTasks();
                _showSnackBar('已清空');
              },
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('全部'),
                  if (_allTasks.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    _buildBadge(_allTasks.length),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.upload, size: 16),
                  const SizedBox(width: 4),
                  const Text('发送'),
                  if (_sendingTasks.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    _buildBadge(_sendingTasks.length),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.download, size: 16),
                  const SizedBox(width: 4),
                  const Text('接收'),
                  if (_receivingTasks.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    _buildBadge(_receivingTasks.length),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildInfoPanel(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTaskList(_allTasks),
                _buildTaskList(_sendingTasks),
                _buildTaskList(_receivingTasks),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: widget.selectedDevice != null
          ? FloatingActionButton.extended(
              onPressed: _pickAndSendFiles,
              icon: const Icon(Icons.send),
              label: const Text('发送文件'),
            )
          : FloatingActionButton.extended(
              onPressed: () => _showSnackBar('请先连接设备'),
              icon: const Icon(Icons.link_off),
              label: const Text('未连接'),
              backgroundColor: Colors.grey,
            ),
    );
  }

  /// 构建数量徽章
  Widget _buildBadge(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// 构建任务列表
  Widget _buildTaskList(List<FileTransferTask> tasks) {
    if (tasks.isEmpty) {
      return const EmptyTransferWidget();
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        return TransferItemWidget(
          key: ValueKey(task.id),
          task: task,
          onPause: task.canPause
              ? () => _transferService.pauseTask(task.id)
              : null,
          onResume: task.canResume && widget.selectedDevice != null
              ? () => _transferService.resumeTask(task.id, widget.selectedDevice!)
              : null,
          onCancel: task.canCancel
              ? () => _transferService.cancelTask(task.id)
              : null,
          onRemove: !task.isActive
              ? () => _transferService.removeTask(task.id)
              : null,
          onOpen: task.status == TransferStatus.completed &&
                  task.direction == TransferDirection.receive
              ? () => _openFile(task)
              : null,
        );
      },
    );
  }
}
