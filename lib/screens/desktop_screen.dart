import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/device.dart';
import '../models/clipboard_data.dart';
import '../models/received_message.dart';
import '../models/app_entry.dart';
import '../models/remote_request.dart';
import '../services/discovery_service.dart';
import '../services/socket_service.dart';
import '../services/clipboard_service.dart';
import '../services/clipboard_watcher_service.dart';
import '../services/auth_service.dart';
import '../services/encryption_service.dart';
import '../services/desktop_app_service.dart';
import '../services/windows_process_service.dart';
import '../services/windows_window_service.dart';
import 'package:cryptography/cryptography.dart';

import 'settings_screen.dart';
import 'file_transfer_screen.dart';
import '../services/file_transfer_service.dart';
import '../models/file_transfer.dart';
import '../widgets/desktop/desktop_app_bar.dart';
import '../widgets/desktop/desktop_background.dart';
import '../widgets/desktop/desktop_history_panel.dart';
import '../widgets/desktop/desktop_status_card.dart';

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
  final _fileTransferService = FileTransferService();
  final _desktopAppService = DesktopAppService();
  final _processService = WindowsProcessService();
  
  int _activeTransferCount = 0;
  StreamSubscription<List<FileTransferTask>>? _transferSubscription;
  
  String _localIp = '获取中...';
  int _tcpPort = SocketService.defaultPort;
  bool _isRunning = false;
  bool _showHistory = false;  // 默认关闭历史记录
  bool _autoPaste = false;    // 自动粘贴功能，默认关闭
  bool _passwordEnabled = false;  // 密码保护功能
  bool _encryptionEnabled = false;
  SecretKey? _encryptionKey;

  bool _syncToMobile = false;     // 同步剪贴板到手机
  final List<ReceivedMessage> _messages = [];
  final List<Device> _connectedDevices = []; // 已连接的手机设备
  
  StreamSubscription<AuthResult>? _messageSubscription;
  StreamSubscription<Device>? _connectedDeviceSubscription;
  StreamSubscription<ClipboardContent>? _clipboardSubscription;
  Timer? _keepAliveTimer;  // 保活定时器，防止窗口失焦时事件循环被降低优先级
  StreamSubscription<FileTransferTask>? _transferRequestSubscription;
  
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
    final encryptionEnabled = await EncryptionService.isEncryptionEnabled();
    var effectiveEncryptionEnabled = encryptionEnabled;
    var resetEncryption = false;

    // 未启用密码时强制关闭加密，避免解密失败
    if (encryptionEnabled && !passwordEnabled) {
      await EncryptionService.setEncryptionEnabled(false);
      effectiveEncryptionEnabled = false;
      resetEncryption = true;
    }
    
    setState(() {
      _autoPaste = prefs.getBool(_autoPasteKey) ?? false;
      _syncToMobile = prefs.getBool(_syncToMobileKey) ?? false;
      _passwordEnabled = passwordEnabled;
      _encryptionEnabled = effectiveEncryptionEnabled;
    });

    if (resetEncryption && mounted) {
      _showSnackBar('未设置密码，已关闭加密');
    }

    if (effectiveEncryptionEnabled && passwordEnabled) {
      final hash = await AuthService.getPasswordHash();
      if (hash != null) {
        _encryptionKey = await EncryptionService.deriveKey(hash);
      }
    } else {
      _encryptionKey = null;
    }
  }

  @override
  void dispose() {
    _keepAliveTimer?.cancel();
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    _messageSubscription?.cancel();
    _connectedDeviceSubscription?.cancel();
    _clipboardSubscription?.cancel();
    _transferSubscription?.cancel();
    _transferRequestSubscription?.cancel();
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
      
      _socketService.setEncryption(
        enabled: _encryptionEnabled,
        key: _encryptionKey,
      );

      // 设置请求处理器
      _socketService.setRequestHandler(handler: _handleRequest);
      
      // 启动 TCP 服务器
      _tcpPort = await _socketService.startServer();
      
      // 启动 UDP 发现监听
      final deviceName = Platform.localHostname;
      // 获取密码盐值（如果启用了密码）
      final salt = _passwordEnabled ? await AuthService.getSalt() : null;
      _discoveryService.setSalt(salt);
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

      // 启动文件传输服务
      await _fileTransferService.startServer();
      _fileTransferService.setEncryption(enabled: _encryptionEnabled, key: _encryptionKey);
      
      // 监听文件传输任务
      _transferSubscription = _fileTransferService.taskStream.listen((tasks) {
        if (mounted) {
          setState(() {
            _activeTransferCount = tasks.where((t) => t.isActive).length;
          });
        }
      });

      // 监听文件接收请求
      _transferRequestSubscription = _fileTransferService.requestStream.listen((task) async {
        final autoAccept = await _fileTransferService.isAutoAcceptEnabled();
        if (autoAccept) {
          if (mounted) {
            _showSnackBar('已自动接收 ${task.fileName}');
          }
          return;
        }
        if (mounted) {
          _showIncomingFileDialog(task);
        }
      });

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
  
  /// 更新密码相关设置到服务
  Future<void> _updatePasswordSettings() async {
    _socketService.setPasswordVerification(
      requiresPassword: _passwordEnabled,
      verifyPassword: AuthService.verifyHash,
    );
    _discoveryService.setRequiresPassword(_passwordEnabled);
    // 更新盐值
    final salt = _passwordEnabled ? await AuthService.getSalt() : null;
    _discoveryService.setSalt(salt);
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
      _messages.insert(0, ReceivedMessage(
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

  /// 处理手机端请求
  Future<RemoteResponse?> _handleRequest(RemoteRequest request) async {
    switch (request.action) {
      case 'app_list':
        final apps = await _desktopAppService.loadApps();
        return RemoteResponse.ok(
          request.id,
          data: apps.map((e) => e.toJson()).toList(),
        );
      case 'app_upsert':
        final app = _parseAppEntry(request.payload);
        if (app == null) {
          return RemoteResponse.fail(request.id, '应用参数无效');
        }
        final apps = await _desktopAppService.upsert(app);
        return RemoteResponse.ok(
          request.id,
          data: apps.map((e) => e.toJson()).toList(),
        );
      case 'app_remove':
        final id = request.payload?['id'];
        if (id is! String || id.isEmpty) {
          return RemoteResponse.fail(request.id, '应用 ID 无效');
        }
        final apps = await _desktopAppService.remove(id);
        return RemoteResponse.ok(
          request.id,
          data: apps.map((e) => e.toJson()).toList(),
        );
      case 'app_launch':
        final id = request.payload?['id'];
        if (id is! String || id.isEmpty) {
          return RemoteResponse.fail(request.id, '应用 ID 无效');
        }
        final ok = await _desktopAppService.launchById(id);
        if (!ok) {
          return RemoteResponse.fail(request.id, '启动失败');
        }
        return RemoteResponse.ok(request.id, data: {'launched': true});
      case 'process_list':
        final list = await _processService.listProcesses();
        return RemoteResponse.ok(
          request.id,
          data: list.map((e) => e.toJson()).toList(),
        );
      case 'process_activate':
        final pid = _parsePid(request.payload?['pid']);
        if (pid == null) {
          return RemoteResponse.fail(request.id, 'PID 无效');
        }
        final ok = await WindowsWindowService.activateProcess(pid);
        if (!ok) {
          return RemoteResponse.fail(request.id, '激活失败');
        }
        return RemoteResponse.ok(request.id, data: {'activated': true});
      default:
        return RemoteResponse.fail(request.id, '未知指令');
    }
  }

  AppEntry? _parseAppEntry(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    final appJson = payload['app'];
    if (appJson is! Map<String, dynamic>) return null;
    return AppEntry.tryFromJson(appJson);
  }

  int? _parsePid(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
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
  
  /// 打开设置页面
  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          callbacks: SettingsCallbacks(
            onAutoPasteChanged: (value) => setState(() => _autoPaste = value),
            onSyncToMobileChanged: (value) {
              setState(() => _syncToMobile = value);
              if (value) {
                _clipboardWatcher.startWatching();
              } else {
                _clipboardWatcher.stopWatching();
              }
            },
            onPasswordChanged: (value) {
              setState(() => _passwordEnabled = value);
              _updatePasswordSettings();
            },
            onEncryptionChanged: (value) async {
              if (value && !_passwordEnabled) {
                _showSnackBar('请先启用密码保护');
                setState(() => _encryptionEnabled = false);
                _socketService.setEncryption(enabled: false, key: null);
                _fileTransferService.setEncryption(enabled: false, key: null);
                return;
              }
              setState(() => _encryptionEnabled = value);
              if (value && _passwordEnabled) {
                final hash = await AuthService.getPasswordHash();
                if (hash != null) {
                  _encryptionKey = await EncryptionService.deriveKey(hash);
                }
              } else {
                _encryptionKey = null;
              }
              _socketService.setEncryption(enabled: value, key: _encryptionKey);
              _fileTransferService.setEncryption(enabled: value, key: _encryptionKey);
            },
          ),
        ),
      ),
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
      appBar: DesktopAppBar(
        activeTransferCount: _activeTransferCount,
        onOpenSettings: _openSettings,
        onLockPhone: _connectedDevices.any((d) => d.syncPort != null)
            ? _sendPhoneLockCommand
            : null,
        onOpenTransfer: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const FileTransferScreen(),
            ),
          );
        },
        onMinimize: Platform.isWindows ? () => windowManager.hide() : null,
      ),
      body: Stack(
        children: [
          const DesktopBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DesktopStatusCard(
                    isRunning: _isRunning,
                    localIp: _localIp,
                    tcpPort: _tcpPort,
                    connectedDeviceCount: _connectedDevices.length,
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: DesktopHistoryPanel(
                      showHistory: _showHistory,
                      messages: _messages,
                      onClear: () => setState(() => _messages.clear()),
                      onToggle: (value) => setState(() => _showHistory = value),
                      onCopy: (message) async {
                        await ClipboardService.copy(message.content);
                        _showSnackBar('已复制');
                      },
                      onOpen: _showMessageDetail,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showMessageDetail(ReceivedMessage msg) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.message_outlined, size: 20),
            const SizedBox(width: 8),
            const Text('消息详情'),
            const Spacer(),
            Text(
              _formatTime(msg.time),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 300),
          child: SingleChildScrollView(
            child: SelectableText(
              msg.content,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              await ClipboardService.copy(msg.content);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已复制'),
                    duration: Duration(seconds: 1),
                  ),
                );
                navigator.pop();
              }
            },
            child: const Text('复制并关闭'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }

  Future<void> _sendPhoneLockCommand() async {
    final device = await _pickDeviceForMobileControl();
    if (device == null) return;

    await _socketService.pushCommandToDevices([device], cmdPhoneLock);
    _showSnackBar('已发送锁屏指令');
  }

  Future<Device?> _pickDeviceForMobileControl() async {
    final devices = _connectedDevices.where((d) => d.syncPort != null).toList();
    if (devices.isEmpty) {
      _showSnackBar('未发现可控制的手机');
      return null;
    }
    if (devices.length == 1) return devices.first;

    return showModalBottomSheet<Device>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView.separated(
          itemCount: devices.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final device = devices[index];
            return ListTile(
              title: Text(device.name),
              subtitle: Text('${device.ip}:${device.syncPort}'),
              onTap: () => Navigator.pop(context, device),
            );
          },
        ),
      ),
    );
  }
}
