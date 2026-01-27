import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device.dart';
import '../models/clipboard_data.dart';
import '../services/discovery_service.dart';
import '../services/socket_service.dart';
import '../services/auth_service.dart';
import '../services/encryption_service.dart';
import 'package:cryptography/cryptography.dart';
import '../services/clipboard_service.dart' show cmdBackspace, cmdSpace, cmdClear, cmdEnter, cmdArrowUp, cmdArrowDown, cmdArrowLeft, cmdArrowRight, cmdShutdown, cmdShutdownCancel, cmdShutdownNow;
import '../services/clipboard_sync_service.dart';
import '../services/mobile_clipboard_helper.dart';
import 'touchpad_screen.dart';
import 'simple_input_screen.dart';
import 'settings_screen.dart';
import 'text_memory_screen.dart';
import '../services/input_method_service.dart';
import '../services/text_memory_service.dart';

// 自动发送设置的存储键
const String _autoSendEnabledKey = 'auto_send_enabled';
const String _autoSendDelayKey = 'auto_send_delay';
const String _receiveFromPcKey = 'receive_from_pc_enabled';

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
  final _clipboardSyncService = ClipboardSyncService();
  final _inputFocusNode = FocusNode(); // 输入框焦点
  final _textMemoryService = TextMemoryService();
  
  final List<Device> _devices = [];
  Device? _selectedDevice;
  bool _isSearching = false;
  bool _isSending = false;
  bool _receiveFromPc = false;     // 是否接收电脑剪贴板
  int _syncPort = 0;               // 剪贴板同步监听端口
  bool _encryptionEnabled = false;
  SecretKey? _encryptionKey;
  
  // 存储设备对应的密码哈希（用户输入后缓存）
  final Map<String, String> _devicePasswords = {};
  
  StreamSubscription<Device>? _deviceSubscription;
  StreamSubscription<ClipboardContent>? _syncSubscription;
  
  // 自动发送相关状态
  bool _autoSendEnabled = false;
  double _autoSendDelay = 3.0; // 默认3秒，支持小数
  Timer? _autoSendTimer;
  int _countdownSeconds = 0; // 倒计时剩余秒数
  Timer? _countdownTimer; // 倒计时显示定时器
  Timer? _longPressTimer; // 长按连续触发定时器
  
  int _memoryCount = 0; // 文本记忆数量

  @override
  void initState() {
    super.initState();
    _initialize();
    
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
    
    // 监听电脑推送的剪贴板内容
    _syncSubscription = _clipboardSyncService.contentStream.listen((content) {
      _onClipboardReceived(content);
    });
    
    // 监听输入变化，触发自动发送计时
    _textController.addListener(_onTextChanged);
  }
  
  /// 初始化：加载设置 -> 搜索设备（确保顺序执行）
  Future<void> _initialize() async {
    await _loadSettings();
    await _loadMemoryCount();
    // 设置加载完成后再搜索设备，确保 syncPort 已就绪
    if (mounted) {
      _searchDevices();
    }
  }
  
  /// 加载文本记忆数量
  Future<void> _loadMemoryCount() async {
    final count = await _textMemoryService.getCount();
    if (mounted) {
      setState(() => _memoryCount = count);
    }
  }
  
  /// 加载设置
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final receiveFromPc = prefs.getBool(_receiveFromPcKey) ?? false;
    final encryptionEnabled = await EncryptionService.isEncryptionEnabled();
    
    setState(() {
      _autoSendEnabled = prefs.getBool(_autoSendEnabledKey) ?? false;
      _autoSendDelay = prefs.getDouble(_autoSendDelayKey) ?? 3.0;
      _receiveFromPc = receiveFromPc;
      _encryptionEnabled = encryptionEnabled;
    });
    
    // 如果启用了接收功能，启动同步服务
    if (receiveFromPc) {
      await _startSyncService();
    }
  }
  
  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _inputFocusNode.dispose();
    _deviceSubscription?.cancel();
    _syncSubscription?.cancel();
    _discoveryService.dispose();
    _socketService.dispose();
    _clipboardSyncService.dispose();
    _cancelAutoSendTimer();
    _longPressTimer?.cancel();
    super.dispose();
  }
  
  /// 输入变化时的回调
  void _onTextChanged() {
    if (!_autoSendEnabled) return;
    
    // 取消之前的计时器
    _cancelAutoSendTimer();
    
    final content = _textController.text.trimRight();
    // 内容为空或没有选择设备，不启动计时
    if (content.trim().isEmpty || _selectedDevice == null || _isSending) {
      return;
    }
    
    // 启动倒计时
    _countdownSeconds = _autoSendDelay.ceil();
    setState(() {});
    
    // 每秒更新倒计时显示
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _countdownSeconds--;
      });
      if (_countdownSeconds <= 0) {
        timer.cancel();
      }
    });
    
    // 延迟后发送（支持小数秒）
    _autoSendTimer = Timer(Duration(milliseconds: (_autoSendDelay * 1000).toInt()), () {
      _countdownTimer?.cancel();
      setState(() {
        _countdownSeconds = 0;
      });
      _sendContent();
    });
  }
  
  /// 取消自动发送计时器
  void _cancelAutoSendTimer() {
    _autoSendTimer?.cancel();
    _autoSendTimer = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    if (_countdownSeconds > 0) {
      setState(() {
        _countdownSeconds = 0;
      });
    }
  }
  
  /// 启动剪贴板同步服务
  Future<void> _startSyncService() async {
    _clipboardSyncService.setEncryption(enabled: _encryptionEnabled, key: _encryptionKey);
    final port = await _clipboardSyncService.startServer();
    setState(() => _syncPort = port);
  }
  
  /// 停止剪贴板同步服务
  Future<void> _stopSyncService() async {
    await _clipboardSyncService.stopServer();
    setState(() => _syncPort = 0);
  }
  
  /// 处理接收到的电脑剪贴板内容
  Future<void> _onClipboardReceived(ClipboardContent content) async {
    final success = await MobileClipboardHelper.writeContent(content);
    
    if (!success) {
      _showSnackBar('接收失败');
    }
  }

  /// 搜索设备
  Future<void> _searchDevices() async {
    setState(() {
      _isSearching = true;
      _devices.clear();
      _selectedDevice = null;
    });

    // 携带同步端口(如果启用了接收功能)
    await _discoveryService.sendDiscoveryBroadcast(
      syncPort: _receiveFromPc ? _syncPort : null,
    );

    // 等待搜索完成
    await Future.delayed(const Duration(seconds: 3));

    setState(() {
      _isSearching = false;
    });
    
    // 未发现设备时提示
    if (_devices.isEmpty) {
      _showSnackBar('未发现设备');
    }
  }

  /// 发送内容
  Future<void> _sendContent() async {
    if (_selectedDevice == null) {
      _showSnackBar('请先选择目标设备');
      return;
    }

    // 检查是否有内容（trim判断），但发送时保留头部空格（只trimRight）
    final text = _textController.text;
    if (text.trim().isEmpty) {
      _showSnackBar('请输入要发送的内容');
      return;
    }
    final content = text.trimRight();

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
        // 使用设备提供的盐值计算哈希
        final salt = _selectedDevice!.salt ?? '';
        passwordHash = AuthService.hashPassword(password, salt);
        _devicePasswords[deviceKey] = passwordHash; // 缓存密码哈希
        if (_encryptionEnabled) {
          // 使用密码哈希派生密钥，确保与电脑端一致
          _encryptionKey = await EncryptionService.deriveKey(passwordHash);
        }
      }
    }

    setState(() {
      _isSending = true;
    });

    _socketService.setEncryption(enabled: _encryptionEnabled, key: _encryptionKey);
    final result = await _socketService.sendMessage(
      _selectedDevice!.ip,
      _selectedDevice!.port,
      content,
      passwordHash: passwordHash,
    );

    setState(() {
      _isSending = false;
    });

    if (result.success) {
      _textController.clear();
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
  
  /// 发送控制指令到电脑
  /// [silent] 为 true 时不显示提示（用于长按连续触发）
  Future<void> _sendCommand(String command, String label, {bool silent = false}) async {
    if (_selectedDevice == null) {
      if (!silent) _showSnackBar('请先选择目标设备');
      return;
    }
    
    // 取消自动发送计时器
    _cancelAutoSendTimer();
    
    // 获取密码（如果需要）
    String? passwordHash;
    if (_selectedDevice!.requiresPassword) {
      final deviceKey = '${_selectedDevice!.ip}:${_selectedDevice!.port}';
      passwordHash = _devicePasswords[deviceKey];
      if (passwordHash == null) {
        if (silent) return; // 长按时不弹密码框
        final password = await _showPasswordDialog();
        if (password == null) return;
        // 使用设备提供的盐值计算哈希
        final salt = _selectedDevice!.salt ?? '';
        passwordHash = AuthService.hashPassword(password, salt);
        _devicePasswords[deviceKey] = passwordHash;
        if (_encryptionEnabled) {
          // 使用密码哈希派生密钥，确保与电脑端一致
          _encryptionKey = await EncryptionService.deriveKey(passwordHash);
        }
      }
    }
    
    _socketService.setEncryption(enabled: _encryptionEnabled, key: _encryptionKey);
    final result = await _socketService.sendMessage(
      _selectedDevice!.ip,
      _selectedDevice!.port,
      command,
      passwordHash: passwordHash,
    );
    
    if (!silent && !result.success) {
      _showSnackBar('发送失败');
    }
  }
  
  /// 构建快捷操作按钮
  Widget _buildCommandButton({
    required IconData icon,
    required String label,
    required String command,
    Color? color,
  }) {
    return OutlinedButton(
      onPressed: _selectedDevice == null ? null : () => _sendCommand(command, label),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
  
  /// 构建支持长按连续触发的快捷操作按钮
  Widget _buildCommandButtonWithLongPress({
    required IconData icon,
    required String label,
    required String command,
    Color? color,
  }) {
    final isDisabled = _selectedDevice == null;
    
    return GestureDetector(
      onLongPressStart: isDisabled ? null : (_) {
        // 长按开始：立即发送一次，然后每 100ms 连续发送（静默模式）
        _sendCommand(command, label);
        _longPressTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
          _sendCommand(command, label, silent: true);
        });
      },
      onLongPressEnd: isDisabled ? null : (_) {
        // 长按结束：停止定时器
        _longPressTimer?.cancel();
        _longPressTimer = null;
      },
      child: OutlinedButton(
        onPressed: isDisabled ? null : () => _sendCommand(command, label),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
  
  /// 打开触摸板页面
  void _openTouchpad() {
    if (_selectedDevice == null) return;
    
    // 获取当前设备的密码哈希
    final deviceKey = '${_selectedDevice!.ip}:${_selectedDevice!.port}';
    final passwordHash = _devicePasswords[deviceKey];
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TouchpadScreen(
          device: _selectedDevice!,
          passwordHash: passwordHash,
        ),
      ),
    );
  }
  
  /// 打开简洁输入页面
  void _openSimpleInput() {
    if (_selectedDevice == null) return;
    
    final deviceKey = '${_selectedDevice!.ip}:${_selectedDevice!.port}';
    final passwordHash = _devicePasswords[deviceKey];
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SimpleInputScreen(
          device: _selectedDevice!,
          passwordHash: passwordHash,
        ),
      ),
    );
  }
  
  /// 暂存当前输入内容到本地
  Future<void> _saveToMemory() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      _showSnackBar('请输入要暂存的内容');
      return;
    }
    
    await _textMemoryService.add(text);
    _textController.clear();
    await _loadMemoryCount();
    _showSnackBar('已暂存');
  }
  
  /// 保存设备信息供悬浮窗使用
  Future<void> _saveDeviceForOverlay(Device? device) async {
    if (device == null) return;
    final prefs = await SharedPreferences.getInstance();
    final deviceJson = '{"ip":"${device.ip}","port":${device.port},"name":"${device.name}"}';
    await prefs.setString('overlay_selected_device', deviceJson);
  }
  
  /// 打开文本记忆页面
  void _openTextMemory() {
    if (_selectedDevice == null) return;
    
    final deviceKey = '${_selectedDevice!.ip}:${_selectedDevice!.port}';
    final passwordHash = _devicePasswords[deviceKey];
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TextMemoryScreen(
          device: _selectedDevice!,
          passwordHash: passwordHash,
        ),
      ),
    ).then((_) {
      // 返回时刷新记忆数量
      _loadMemoryCount();
    });
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
            // 标题
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                '电脑电源控制',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            // 定时关机选项
            ListTile(
              leading: const Icon(Icons.timer, color: Colors.orange),
              title: const Text('定时关机'),
              subtitle: const Text('设置倒计时后自动关机'),
              onTap: () {
                Navigator.pop(context);
                _showShutdownTimerDialog();
              },
            ),
            // 取消关机
            ListTile(
              leading: const Icon(Icons.cancel_outlined, color: Colors.blue),
              title: const Text('取消关机'),
              subtitle: const Text('取消已设置的定时关机'),
              onTap: () {
                Navigator.pop(context);
                _sendCommand(cmdShutdownCancel, '取消关机');
              },
            ),
            // 立即关机
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
            // 预设时间选项
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
            // 自定义时间
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
  
  /// 打开设置页面
  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          callbacks: SettingsCallbacks(
            onReceiveFromPcChanged: (value) {
              setState(() => _receiveFromPc = value);
              if (value) {
                _startSyncService();
              } else {
                _stopSyncService();
              }
            },
            onAutoSendChanged: (value) {
              setState(() {
                _autoSendEnabled = value;
                if (!value) _cancelAutoSendTimer();
              });
            },
            onAutoSendDelayChanged: (value) {
              setState(() => _autoSendDelay = value);
              _cancelAutoSendTimer();
            },
            onEncryptionChanged: (value) {
              setState(() => _encryptionEnabled = value);
              _clipboardSyncService.setEncryption(enabled: value, key: _encryptionKey);
            },
          ),
        ),
      ),
    );
  }
  
  /// 构建方向键按钮（支持长按连续触发）
  Widget _buildArrowButton(IconData icon, String command, String label) {
    final isDisabled = _selectedDevice == null;
    
    return SizedBox(
      width: 48,
      height: 48,
      child: GestureDetector(
        onLongPressStart: isDisabled ? null : (_) {
          // 长按开始：立即发送一次，然后每 100ms 连续发送
          _sendCommand(command, label, silent: true);
          _longPressTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
            _sendCommand(command, label, silent: true);
          });
        },
        onLongPressEnd: isDisabled ? null : (_) {
          _longPressTimer?.cancel();
          _longPressTimer = null;
        },
        child: OutlinedButton(
          onPressed: isDisabled ? null : () => _sendCommand(command, label, silent: true),
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Icon(icon, size: 24),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LAN Clip - 发送端'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // 切换输入法按钮（仅 Android）
          if (InputMethodService.isSupported)
            IconButton(
              icon: const Icon(Icons.keyboard),
              tooltip: '切换输入法',
              onPressed: () => InputMethodService.showInputMethodPicker(),
            ),
          // 电源控制按钮
          IconButton(
            icon: const Icon(Icons.power_settings_new),
            tooltip: '电源控制',
            onPressed: _selectedDevice == null ? null : _showPowerMenu,
          ),
          // 简洁输入页面入口
          IconButton(
            icon: const Icon(Icons.edit_note),
            tooltip: '简洁输入',
            onPressed: _selectedDevice == null ? null : _openSimpleInput,
          ),
          // 触摸板入口按钮
          IconButton(
            icon: const Icon(Icons.touch_app),
            tooltip: '触摸板',
            onPressed: _selectedDevice == null ? null : _openTouchpad,
          ),
          // 设置入口
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: _openSettings,
          ),
        ],
      ),
      // 使用默认的 resizeToAvoidBottomInset: true，让 Flutter 自动调整
      body: Column(
        children: [
          // 主内容区域 - 可滚动，widget 树结构保持不变
          Expanded(
            child: SingleChildScrollView(
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
                              const Text('目标设备', style: TextStyle(fontSize: 16)),
                              Row(
                                children: [
                                  // 断开连接按钮 - 仅在已连接时显示
                                  if (_selectedDevice != null)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: OutlinedButton(
                                        onPressed: () {
                                          setState(() => _selectedDevice = null);
                                          _showSnackBar('已断开连接');
                                        },
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.red,
                                        ),
                                        child: const Text('断开'),
                                      ),
                                    ),
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
                                // 保存设备信息供悬浮窗使用
                                _saveDeviceForOverlay(device);
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // 输入区域 - 固定高度，避免布局变化
                  SizedBox(
                    height: 150,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: TextField(
                          controller: _textController,
                          focusNode: _inputFocusNode,
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
                  
                  // 自动发送倒计时提示
                  if (_countdownSeconds > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              value: _countdownSeconds / _autoSendDelay,
                              color: Colors.blue,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${_autoSendDelay.toStringAsFixed(1)}秒后发送($_countdownSeconds)...',
                            style: const TextStyle(color: Colors.blue),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _cancelAutoSendTimer,
                            child: const Text(
                              '取消',
                              style: TextStyle(
                                color: Colors.red,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  
                  // 文本记忆入口按钮
                  // 未连接时: 暂存按钮 / 已连接时: 进入记忆列表按钮
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_selectedDevice == null)
                        // 未连接 - 暂存按钮
                        OutlinedButton.icon(
                          onPressed: _saveToMemory,
                          icon: const Icon(Icons.save_alt, size: 18),
                          label: Text(_memoryCount > 0 ? '暂存 ($_memoryCount)' : '暂存'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.orange,
                          ),
                        )
                      else
                        // 已连接 - 进入记忆列表
                        OutlinedButton.icon(
                          onPressed: _memoryCount > 0 ? _openTextMemory : _saveToMemory,
                          icon: Icon(
                            _memoryCount > 0 ? Icons.inventory_2_outlined : Icons.save_alt,
                            size: 18,
                          ),
                          label: Text(_memoryCount > 0 ? '记忆 ($_memoryCount)' : '暂存'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _memoryCount > 0 ? Colors.green : Colors.orange,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  // 快捷操作按钮 - 第一行（退格/空格/回车支持长按连续触发）
                  Row(
                    children: [
                      Expanded(
                        child: _buildCommandButtonWithLongPress(
                          icon: Icons.backspace_outlined,
                          label: '退格',
                          command: cmdBackspace,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildCommandButtonWithLongPress(
                          icon: Icons.space_bar,
                          label: '空格',
                          command: cmdSpace,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildCommandButtonWithLongPress(
                          icon: Icons.keyboard_return,
                          label: '回车',
                          command: cmdEnter,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildCommandButton(
                          icon: Icons.clear_all,
                          label: '清空',
                          command: cmdClear,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  // 快捷操作按钮 - 方向键
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildArrowButton(Icons.keyboard_arrow_left, cmdArrowLeft, '左'),
                      const SizedBox(width: 4),
                      Column(
                        children: [
                          _buildArrowButton(Icons.keyboard_arrow_up, cmdArrowUp, '上'),
                          const SizedBox(height: 4),
                          _buildArrowButton(Icons.keyboard_arrow_down, cmdArrowDown, '下'),
                        ],
                      ),
                      const SizedBox(width: 4),
                      _buildArrowButton(Icons.keyboard_arrow_right, cmdArrowRight, '右'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  
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
          ),
        ],
      ),
    );
  }
}
