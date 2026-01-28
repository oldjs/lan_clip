part of 'mobile_screen.dart';

extension _MobileScreenStateDialogs on _MobileScreenState {
  /// 显示密码输入对话框
  Future<String?> _showPasswordDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('输入连接密码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '该设备需要密码才能连接',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '密码',
                border: OutlineInputBorder(),
                hintText: '请输入密码',
              ),
              autofocus: true,
              onSubmitted: (value) {
                Navigator.pop(context, value.trim());
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final password = controller.text.trim();
              Navigator.pop(context, password.isEmpty ? null : password);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 显示接收确认对话框
  Future<void> _showIncomingFileDialog(FileTransferTask task) async {
    final downloadPath = await _fileTransferService.getDownloadPath();
    var autoAccept = await _fileTransferService.isAutoAcceptEnabled();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('接收文件'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('文件: ${task.fileName}'),
                  const SizedBox(height: 6),
                  Text('大小: ${task.formattedSize}'),
                  const SizedBox(height: 6),
                  Text('保存到: $downloadPath'),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('始终自动接收'),
                    value: autoAccept,
                    onChanged: (value) async {
                      setState(() => autoAccept = value);
                      await _fileTransferService.setAutoAcceptEnabled(value);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _fileTransferService.rejectTask(task.id);
                  },
                  child: const Text('拒绝'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _fileTransferService.acceptTask(task.id);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const FileTransferScreen(),
                      ),
                    );
                  },
                  child: const Text('接收'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 显示关机控制菜单
  void _showPowerMenu() {
    if (_selectedDevice == null) {
      _showSnackBar('请先选择目标设备');
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                '电脑电源控制',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.timer, color: Colors.orange),
              title: const Text('定时关机'),
              subtitle: const Text('设置倒计时后自动关机'),
              onTap: () {
                Navigator.pop(context);
                _showShutdownTimerDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.cancel_outlined, color: Colors.blue),
              title: const Text('取消关机'),
              subtitle: const Text('取消已设置的定时关机'),
              onTap: () {
                Navigator.pop(context);
                _sendCommand(cmdShutdownCancel, '取消关机');
              },
            ),
            ListTile(
              leading: const Icon(Icons.power_settings_new, color: Colors.red),
              title: const Text('立即关机'),
              subtitle: const Text('电脑将立即关机'),
              onTap: () {
                Navigator.pop(context);
                _confirmShutdownNow();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 显示定时关机时间选择对话框
  void _showShutdownTimerDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('定时关机'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('选择关机时间:', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildTimerChip(context, '30秒', 30),
                _buildTimerChip(context, '1分钟', 60),
                _buildTimerChip(context, '5分钟', 300),
                _buildTimerChip(context, '10分钟', 600),
                _buildTimerChip(context, '30分钟', 1800),
                _buildTimerChip(context, '1小时', 3600),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () {
                Navigator.pop(context);
                _showCustomTimerDialog();
              },
              child: const Text('自定义时间'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  /// 构建时间选择按钮
  Widget _buildTimerChip(BuildContext context, String label, int seconds) {
    return ActionChip(
      label: Text(label),
      onPressed: () {
        Navigator.pop(context);
        _sendCommand('$cmdShutdown:$seconds', '定时关机 $label');
      },
    );
  }

  /// 显示自定义时间输入对话框
  void _showCustomTimerDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('自定义关机时间'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '分钟数',
            hintText: '输入分钟数',
            border: OutlineInputBorder(),
            suffixText: '分钟',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final minutes = int.tryParse(controller.text) ?? 0;
              if (minutes > 0) {
                Navigator.pop(context);
                final seconds = minutes * 60;
                _sendCommand('$cmdShutdown:$seconds', '定时关机 $minutes 分钟');
              } else {
                _showSnackBar('请输入有效的分钟数');
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 确认立即关机
  void _confirmShutdownNow() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('确认关机'),
          ],
        ),
        content: const Text('电脑将立即关机，未保存的工作可能会丢失。\n\n确定要继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _sendCommand(cmdShutdownNow, '立即关机');
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('确定关机'),
          ),
        ],
      ),
    );
  }
}
