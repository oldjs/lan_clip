import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/discovery_service.dart';
import '../services/socket_service.dart';
import '../services/clipboard_service.dart';

/// 电脑端界面 - 接收内容并写入剪切板
class DesktopScreen extends StatefulWidget {
  const DesktopScreen({super.key});

  @override
  State<DesktopScreen> createState() => _DesktopScreenState();
}

class _DesktopScreenState extends State<DesktopScreen> 
    with TrayListener, WindowListener {
  final _discoveryService = DiscoveryService();
  final _socketService = SocketService();
  
  String _localIp = '获取中...';
  int _tcpPort = SocketService.defaultPort;
  bool _isRunning = false;
  bool _showHistory = false;  // 默认关闭历史记录
  bool _autoPaste = false;    // 自动粘贴功能，默认关闭
  final List<_ReceivedMessage> _messages = [];
  
  StreamSubscription<String>? _messageSubscription;
  
  // 设置项的存储键
  static const String _autoPasteKey = 'auto_paste_enabled';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _initServices();
    _initTray();
    windowManager.addListener(this);
  }

  /// 加载设置
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoPaste = prefs.getBool(_autoPasteKey) ?? false;
    });
  }

  /// 保存自动粘贴设置
  Future<void> _setAutoPaste(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoPasteKey, value);
    setState(() => _autoPaste = value);
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    _messageSubscription?.cancel();
    _discoveryService.dispose();
    _socketService.dispose();
    super.dispose();
  }

  /// 初始化托盘
  Future<void> _initTray() async {
    if (!Platform.isWindows) return;
    
    // 设置托盘图标（使用应用图标）
    await trayManager.setIcon('assets/tray_icon.ico');
    await trayManager.setToolTip('LAN Clip - 局域网剪切板');
    
    // 托盘菜单
    final menu = Menu(
      items: [
        MenuItem(key: 'show', label: '显示窗口'),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: '退出'),
      ],
    );
    await trayManager.setContextMenu(menu);
    trayManager.addListener(this);
  }

  /// 初始化服务
  Future<void> _initServices() async {
    // 获取本机 IP
    final ip = await _discoveryService.getLocalIp();
    setState(() => _localIp = ip ?? '未知');

    // 启动服务
    await _startServer();
  }

  /// 启动服务器
  Future<void> _startServer() async {
    try {
      // 启动 TCP 服务器
      _tcpPort = await _socketService.startServer();
      
      // 启动 UDP 发现监听
      final deviceName = Platform.localHostname;
      await _discoveryService.startListening(deviceName, _tcpPort);
      
      // 监听接收的消息
      _messageSubscription = _socketService.messageStream.listen((message) {
        _onMessageReceived(message);
      });

      setState(() => _isRunning = true);
      
      // 更新托盘提示
      if (Platform.isWindows) {
        await trayManager.setToolTip('LAN Clip - 运行中 ($_localIp)');
      }
    } catch (e) {
      _showSnackBar('服务启动失败: $e');
    }
  }

  /// 处理接收到的消息
  Future<void> _onMessageReceived(String message) async {
    // 写入剪切板
    await ClipboardService.copy(message);
    
    // 添加到消息列表
    setState(() {
      _messages.insert(0, _ReceivedMessage(
        content: message,
        time: DateTime.now(),
      ));
      // 只保留最近 50 条
      if (_messages.length > 50) {
        _messages.removeLast();
      }
    });

    // 自动粘贴功能
    if (_autoPaste) {
      final success = await ClipboardService.simulatePaste();
      _showSnackBar(success ? '已自动粘贴' : '已复制到剪切板');
    } else {
      _showSnackBar('已复制到剪切板');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  // ========== 托盘事件 ==========
  
  @override
  void onTrayIconMouseDown() {
    // 左键点击显示窗口
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    // 右键显示菜单
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        windowManager.show();
        windowManager.focus();
        break;
      case 'exit':
        windowManager.destroy();
        break;
    }
  }

  // ========== 窗口事件 ==========
  
  @override
  void onWindowClose() async {
    // 点击关闭按钮时最小化到托盘
    await windowManager.hide();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LAN Clip - 接收端'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // 最小化到托盘按钮
          if (Platform.isWindows)
            IconButton(
              icon: const Icon(Icons.minimize),
              tooltip: '最小化到托盘',
              onPressed: () => windowManager.hide(),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 服务状态卡片
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isRunning ? Icons.check_circle : Icons.error,
                          color: _isRunning ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isRunning ? '服务运行中' : '服务未启动',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const Divider(),
                    _buildInfoRow('本机 IP', _localIp),
                    _buildInfoRow('发现端口 (UDP)', '9999'),
                    _buildInfoRow('通信端口 (TCP)', '$_tcpPort'),
                    const SizedBox(height: 8),
                    // 自动粘贴设置
                    if (Platform.isWindows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('自动粘贴', style: TextStyle(fontWeight: FontWeight.w500)),
                                  Text(
                                    '收到内容后自动在光标位置粘贴',
                                    style: TextStyle(color: Colors.grey, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _autoPaste,
                              onChanged: _setAutoPaste,
                            ),
                          ],
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, size: 16, color: Colors.blue),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '关闭窗口会最小化到托盘，右键托盘图标可退出',
                              style: TextStyle(color: Colors.blue, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // 接收历史标题栏
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '接收历史',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    if (_messages.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          setState(() => _messages.clear());
                        },
                        child: const Text('清空'),
                      ),
                    Switch(
                      value: _showHistory,
                      onChanged: (v) => setState(() => _showHistory = v),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_showHistory)
              Expanded(
                child: Card(
                  child: _messages.isEmpty
                      ? const Center(
                          child: Text(
                            '暂无记录',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(8),
                          itemCount: _messages.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final msg = _messages[index];
                            return ListTile(
                              title: Text(
                                msg.content,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(_formatTime(msg.time)),
                              trailing: IconButton(
                                icon: const Icon(Icons.copy),
                                onPressed: () async {
                                  await ClipboardService.copy(msg.content);
                                  _showSnackBar('已复制');
                                },
                              ),
                              onTap: () => _showMessageDetail(msg),
                            );
                          },
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          SelectableText(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
           '${time.minute.toString().padLeft(2, '0')}:'
           '${time.second.toString().padLeft(2, '0')}';
  }

  void _showMessageDetail(_ReceivedMessage msg) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('接收时间: ${_formatTime(msg.time)}'),
        content: SelectableText(msg.content),
        actions: [
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              await ClipboardService.copy(msg.content);
              if (mounted) {
                navigator.pop();
                _showSnackBar('已复制');
              }
            },
            child: const Text('复制'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

/// 接收的消息
class _ReceivedMessage {
  final String content;
  final DateTime time;

  _ReceivedMessage({required this.content, required this.time});
}
