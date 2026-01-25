import 'dart:async';
import 'package:flutter/material.dart';
import '../models/device.dart';
import '../services/discovery_service.dart';
import '../services/socket_service.dart';
import '../services/auth_service.dart';

/// 手机端界面 - 输入内容并发送到电脑
class MobileScreen extends StatefulWidget {
  const MobileScreen({super.key});

  @override
  State<MobileScreen> createState() => _MobileScreenState();
}

class _MobileScreenState extends State<MobileScreen> {
  final _textController = TextEditingController();
  final _discoveryService = DiscoveryService();
  final _socketService = SocketService();
  
  final List<Device> _devices = [];
  Device? _selectedDevice;
  bool _isSearching = false;
  bool _isSending = false;
  String _statusMessage = '';
  
  // 存储设备对应的密码哈希（用户输入后缓存）
  final Map<String, String> _devicePasswords = {};
  
  StreamSubscription<Device>? _deviceSubscription;

  @override
  void initState() {
    super.initState();
    _deviceSubscription = _discoveryService.deviceStream.listen((device) {
      setState(() {
        // 避免重复添加
        if (!_devices.contains(device)) {
          _devices.add(device);
        }
        // 自动选择第一个发现的设备
        _selectedDevice ??= device;
      });
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _deviceSubscription?.cancel();
    _discoveryService.dispose();
    _socketService.dispose();
    super.dispose();
  }

  /// 搜索设备
  Future<void> _searchDevices() async {
    setState(() {
      _isSearching = true;
      _devices.clear();
      _selectedDevice = null;
      _statusMessage = '正在搜索设备...';
    });

    await _discoveryService.sendDiscoveryBroadcast();

    // 等待搜索完成
    await Future.delayed(const Duration(seconds: 3));

    setState(() {
      _isSearching = false;
      _statusMessage = _devices.isEmpty ? '未发现设备' : '发现 ${_devices.length} 个设备';
    });
  }

  /// 发送内容
  Future<void> _sendContent() async {
    if (_selectedDevice == null) {
      _showSnackBar('请先选择目标设备');
      return;
    }

    final content = _textController.text.trim();
    if (content.isEmpty) {
      _showSnackBar('请输入要发送的内容');
      return;
    }

    // 如果设备需要密码，先检查是否已有缓存的密码
    String? passwordHash;
    if (_selectedDevice!.requiresPassword) {
      final deviceKey = '${_selectedDevice!.ip}:${_selectedDevice!.port}';
      passwordHash = _devicePasswords[deviceKey];
      
      // 没有缓存密码，需要用户输入
      if (passwordHash == null) {
        final password = await _showPasswordDialog();
        if (password == null) {
          return; // 用户取消
        }
        passwordHash = AuthService.hashPassword(password);
        _devicePasswords[deviceKey] = passwordHash; // 缓存密码哈希
      }
    }

    setState(() {
      _isSending = true;
      _statusMessage = '正在发送...';
    });

    final result = await _socketService.sendMessage(
      _selectedDevice!.ip,
      _selectedDevice!.port,
      content,
      passwordHash: passwordHash,
    );

    setState(() {
      _isSending = false;
      _statusMessage = result.success ? '发送成功' : '发送失败';
    });

    if (result.success) {
      _textController.clear();
      _showSnackBar('已发送到 ${_selectedDevice!.name}');
    } else {
      // 如果是密码错误，清除缓存的密码
      if (_selectedDevice!.requiresPassword) {
        final deviceKey = '${_selectedDevice!.ip}:${_selectedDevice!.port}';
        _devicePasswords.remove(deviceKey);
      }
      _showSnackBar('发送失败: ${result.error ?? "请检查网络连接"}');
    }
  }
  
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

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LAN Clip - 发送端'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 设备选择区域
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('目标设备', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ElevatedButton.icon(
                          onPressed: _isSearching ? null : _searchDevices,
                          icon: _isSearching
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.search),
                          label: Text(_isSearching ? '搜索中' : '搜索'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 提示信息
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, size: 16, color: Colors.orange),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '请先在电脑上打开 LAN Clip，再点击搜索',
                              style: TextStyle(color: Colors.orange, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_devices.isEmpty)
                      const Text('点击搜索按钮发现局域网内的设备', style: TextStyle(color: Colors.grey))
                    else
                      DropdownButton<Device>(
                        isExpanded: true,
                        value: _selectedDevice,
                        hint: const Text('选择设备'),
                        items: _devices.map((device) {
                          return DropdownMenuItem<Device>(
                            value: device,
                            child: Text(device.toString()),
                          );
                        }).toList(),
                        onChanged: (device) {
                          setState(() => _selectedDevice = device);
                        },
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // 输入区域
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    controller: _textController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: const InputDecoration(
                      hintText: '输入要发送到电脑剪切板的内容...',
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // 状态信息
            if (_statusMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(
                  _statusMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            
            // 发送按钮
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: (_isSending || _selectedDevice == null) ? null : _sendContent,
                icon: _isSending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: Text(_isSending ? '发送中...' : '发送到电脑'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
