import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import '../models/device.dart';
import '../models/clipboard_data.dart';
import '../services/discovery_service.dart';
import '../services/socket_service.dart';
import '../services/clipboard_service.dart';
import '../services/clipboard_watcher_service.dart';
import '../services/auth_service.dart';
import '../main.dart' show startHiddenKey;

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
  final _clipboardWatcher = ClipboardWatcherService();
  
  String _localIp = '获取中...';
  int _tcpPort = SocketService.defaultPort;
  bool _isRunning = false;
  bool _showHistory = false;  // 默认关闭历史记录
  bool _autoPaste = false;    // 自动粘贴功能，默认关闭
  bool _passwordEnabled = false;  // 密码保护功能
  bool _launchAtStartup = false;  // 开机自启功能
  bool _startHidden = false;      // 启动时隐藏到托盘
  bool _syncToMobile = false;     // 同步剪贴板到手机
  final List<_ReceivedMessage> _messages = [];
  final List<Device> _connectedDevices = []; // 已连接的手机设备
  
  StreamSubscription<AuthResult>? _messageSubscription;
  StreamSubscription<Device>? _connectedDeviceSubscription;
  StreamSubscription<ClipboardContent>? _clipboardSubscription;
  Timer? _keepAliveTimer;  // 保活定时器，防止窗口失焦时事件循环被降低优先级
  
  // 设置项的存储键
  static const String _autoPasteKey = 'auto_paste_enabled';
  static const String _syncToMobileKey = 'sync_to_mobile_enabled';

  @override
  void initState() {
    super.initState();
    _initialize();
    windowManager.addListener(this);
  }

  /// 按顺序初始化：先加载设置，再启动服务
  Future<void> _initialize() async {
    await _loadSettings();
    await _initServices();
    _initTray();
  }

  /// 加载设置
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final passwordEnabled = await AuthService.isPasswordEnabled();
    
    // 加载开机自启状态
    bool startupEnabled = false;
    if (Platform.isWindows) {
      startupEnabled = await launchAtStartup.isEnabled();
    }
    
    setState(() {
      _autoPaste = prefs.getBool(_autoPasteKey) ?? false;
      _startHidden = prefs.getBool(startHiddenKey) ?? false;
      _syncToMobile = prefs.getBool(_syncToMobileKey) ?? false;
      _passwordEnabled = passwordEnabled;
      _launchAtStartup = startupEnabled;
    });
  }

  /// 保存自动粘贴设置
  Future<void> _setAutoPaste(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoPasteKey, value);
    setState(() => _autoPaste = value);
  }
  
  /// 设置开机自启
  Future<void> _setLaunchAtStartup(bool value) async {
    if (!Platform.isWindows) return;
    
    try {
      if (value) {
        await launchAtStartup.enable();
      } else {
        await launchAtStartup.disable();
      }
      setState(() => _launchAtStartup = value);
    } catch (e) {
      _showSnackBar('设置失败: $e');
    }
  }

  /// 设置启动时隐藏到托盘
  Future<void> _setStartHidden(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(startHiddenKey, value);
    setState(() => _startHidden = value);
  }

  @override
  void dispose() {
    _keepAliveTimer?.cancel();
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    _messageSubscription?.cancel();
    _connectedDeviceSubscription?.cancel();
    _clipboardSubscription?.cancel();
    _discoveryService.dispose();
    _socketService.dispose();
    _clipboardWatcher.dispose();
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
      // 配置密码验证
      _socketService.setPasswordVerification(
        requiresPassword: _passwordEnabled,
        verifyPassword: AuthService.verifyHash,
      );
      
      // 启动 TCP 服务器
      _tcpPort = await _socketService.startServer();
      
      // 启动 UDP 发现监听
      final deviceName = Platform.localHostname;
      await _discoveryService.startListening(
        deviceName, 
        _tcpPort,
        requiresPassword: _passwordEnabled,
      );
      
      // 监听接收的消息
      _messageSubscription = _socketService.messageStream.listen((result) {
        _onAuthResult(result);
      });
      
      // 监听连接的手机设备
      _connectedDeviceSubscription = _discoveryService.connectedDeviceStream.listen((device) {
        _onDeviceConnected(device);
      });
      
      // 监听剪贴板变化(同步到手机)
      _clipboardSubscription = _clipboardWatcher.contentStream.listen((content) {
        _onClipboardChanged(content);
      });
      
      // 如果启用了同步，开始监听剪贴板
      if (_syncToMobile) {
        await _clipboardWatcher.startWatching();
      }

      setState(() => _isRunning = true);
      
      // 启动保活定时器，防止窗口失焦时 Dart 事件循环被降低优先级
      _startKeepAliveTimer();
      
      // 更新托盘提示
      if (Platform.isWindows) {
        await trayManager.setToolTip('LAN Clip - 运行中 ($_localIp)');
      }
    } catch (e) {
      _showSnackBar('服务启动失败: $e');
    }
  }
  
  /// 启动保活定时器
  /// Flutter Windows 在窗口失焦时会降低事件循环优先级，导致 TCP 消息处理延迟
  /// 通过定期触发空操作来保持事件循环活跃
  void _startKeepAliveTimer() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      // 空操作，仅用于保持事件循环活跃
    });
  }
  
  /// 设置密码保护
  Future<void> _setPasswordEnabled(bool value) async {
    if (value) {
      // 启用密码，弹出设置对话框
      final password = await _showSetPasswordDialog();
      if (password != null && password.isNotEmpty) {
        await AuthService.setPassword(password);
        setState(() => _passwordEnabled = true);
        _updatePasswordSettings();
      }
    } else {
      // 关闭密码
      await AuthService.clearPassword();
      setState(() => _passwordEnabled = false);
      _updatePasswordSettings();
    }
  }
  
  /// 更新密码相关设置到服务
  void _updatePasswordSettings() {
    _socketService.setPasswordVerification(
      requiresPassword: _passwordEnabled,
      verifyPassword: AuthService.verifyHash,
    );
    _discoveryService.setRequiresPassword(_passwordEnabled);
  }
  
  /// 显示设置密码对话框
  Future<String?> _showSetPasswordDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('设置连接密码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '设置后，手机连接时需要输入此密码',
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
              if (password.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('密码不能为空')),
                );
                return;
              }
              Navigator.pop(context, password);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 处理认证结果
  void _onAuthResult(AuthResult result) {
    if (result.success && result.message != null) {
      _onMessageReceived(result.message!);
    } else if (!result.success) {
      _showSnackBar('连接被拒绝: ${result.error ?? "密码错误"}');
    }
  }

  /// 处理接收到的消息
  Future<void> _onMessageReceived(String message) async {
    // 检查是否为控制指令
    if (ClipboardService.isCommand(message)) {
      final result = await ClipboardService.executeCommand(message);
      if (result != null) {
        _showSnackBar('已执行: $result');
      }
      return;
    }
    
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
      await ClipboardService.simulatePaste();
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
  
  /// 处理手机设备连接
  void _onDeviceConnected(Device device) {
    setState(() {
      // 避免重复添加
      final exists = _connectedDevices.any((d) => d.ip == device.ip);
      if (!exists) {
        _connectedDevices.add(device);
      } else {
        // 更新已有设备的 syncPort
        final index = _connectedDevices.indexWhere((d) => d.ip == device.ip);
        if (index != -1) {
          _connectedDevices[index] = device;
        }
      }
    });
  }
  
  /// 处理剪贴板变化，推送到手机
  Future<void> _onClipboardChanged(ClipboardContent content) async {
    if (!_syncToMobile || _connectedDevices.isEmpty) return;
    
    // 忽略下一次变化(防止循环)
    _clipboardWatcher.ignoreNextChange();
    
    // 推送到所有已连接的手机
    await _socketService.pushClipboardToDevices(_connectedDevices, content);
    
    // 同步完成，不显示提示
  }
  
  /// 设置同步到手机开关
  Future<void> _setSyncToMobile(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_syncToMobileKey, value);
    
    setState(() => _syncToMobile = value);
    
    if (value) {
      await _clipboardWatcher.startWatching();
    } else {
      await _clipboardWatcher.stopWatching();
    }
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
                    // 开机自启设置 (仅 Windows)
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
                                  Text('开机自启', style: TextStyle(fontWeight: FontWeight.w500)),
                                  Text(
                                    '开机后自动启动程序',
                                    style: TextStyle(color: Colors.grey, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _launchAtStartup,
                              onChanged: _setLaunchAtStartup,
                            ),
                          ],
                        ),
                      ),
                    // 启动时隐藏到托盘设置 (仅 Windows)
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
                                  Text('启动时隐藏', style: TextStyle(fontWeight: FontWeight.w500)),
                                  Text(
                                    '启动后自动最小化到系统托盘',
                                    style: TextStyle(color: Colors.grey, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _startHidden,
                              onChanged: _setStartHidden,
                            ),
                          ],
                        ),
                      ),
                    // 密码保护设置
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('密码保护', style: TextStyle(fontWeight: FontWeight.w500)),
                                Text(
                                  _passwordEnabled ? '已启用，手机连接需要密码' : '未启用，任何人都可连接',
                                  style: TextStyle(
                                    color: _passwordEnabled ? Colors.green : Colors.grey, 
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _passwordEnabled,
                            onChanged: _setPasswordEnabled,
                          ),
                        ],
                      ),
                    ),
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
                    // 同步剪贴板到手机设置
                    if (Platform.isWindows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('同步到手机', style: TextStyle(fontWeight: FontWeight.w500)),
                                  Text(
                                    _syncToMobile 
                                        ? '已启用，复制内容将自动同步到手机 (${_connectedDevices.length}台已连接)' 
                                        : '未启用，手机需开启接收功能',
                                    style: TextStyle(
                                      color: _syncToMobile ? Colors.green : Colors.grey, 
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _syncToMobile,
                              onChanged: _setSyncToMobile,
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
