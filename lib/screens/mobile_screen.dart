import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device.dart';
import '../models/clipboard_data.dart';
import '../services/discovery_service.dart';
import '../services/socket_service.dart';
import '../services/auth_service.dart';
import '../services/clipboard_service.dart' show cmdBackspace, cmdSpace, cmdClear, cmdEnter, cmdArrowUp, cmdArrowDown, cmdArrowLeft, cmdArrowRight;
import '../services/clipboard_sync_service.dart';
import '../services/mobile_clipboard_helper.dart';
import 'touchpad_screen.dart';

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
  
  final List<Device> _devices = [];
  Device? _selectedDevice;
  bool _isSearching = false;
  bool _isSending = false;
  bool _receiveFromPc = false;     // 是否接收电脑剪贴板
  int _syncPort = 0;               // 剪贴板同步监听端口
  
  // 存储设备对应的密码哈希（用户输入后缓存）
  final Map<String, String> _devicePasswords = {};
  
  StreamSubscription<Device>? _deviceSubscription;
  StreamSubscription<ClipboardContent>? _syncSubscription;
  
  // 自动发送相关状态
  bool _autoSendEnabled = false;
  int _autoSendDelay = 3; // 默认3秒
  Timer? _autoSendTimer;
  int _countdownSeconds = 0; // 倒计时剩余秒数
  Timer? _countdownTimer; // 倒计时显示定时器

  @override
  void initState() {
    super.initState();
    _loadSettings();
    
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
    
    // 启动后自动搜索一次设备
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchDevices();
    });
  }
  
  /// 加载设置
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final receiveFromPc = prefs.getBool(_receiveFromPcKey) ?? false;
    
    setState(() {
      _autoSendEnabled = prefs.getBool(_autoSendEnabledKey) ?? false;
      _autoSendDelay = prefs.getInt(_autoSendDelayKey) ?? 3;
      _receiveFromPc = receiveFromPc;
    });
    
    // 如果启用了接收功能，启动同步服务
    if (receiveFromPc) {
      await _startSyncService();
    }
  }
  
  /// 保存自动发送设置
  Future<void> _saveAutoSendSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoSendEnabledKey, _autoSendEnabled);
    await prefs.setInt(_autoSendDelayKey, _autoSendDelay);
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
    super.dispose();
  }
  
  /// 输入变化时的回调
  void _onTextChanged() {
    if (!_autoSendEnabled) return;
    
    // 取消之前的计时器
    _cancelAutoSendTimer();
    
    final content = _textController.text.trim();
    // 内容为空或没有选择设备，不启动计时
    if (content.isEmpty || _selectedDevice == null || _isSending) {
      return;
    }
    
    // 启动倒计时
    _countdownSeconds = _autoSendDelay;
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
    
    // 延迟后发送
    _autoSendTimer = Timer(Duration(seconds: _autoSendDelay), () {
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
    final port = await _clipboardSyncService.startServer();
    setState(() => _syncPort = port);
  }
  
  /// 停止剪贴板同步服务
  Future<void> _stopSyncService() async {
    await _clipboardSyncService.stopServer();
    setState(() => _syncPort = 0);
  }
  
  /// 设置是否接收电脑剪贴板
  Future<void> _setReceiveFromPc(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_receiveFromPcKey, value);
    
    setState(() => _receiveFromPc = value);
    
    if (value) {
      await _startSyncService();
      _showSnackBar('已开启接收电脑剪贴板 (端口: $_syncPort)');
    } else {
      await _stopSyncService();
      _showSnackBar('已关闭接收电脑剪贴板');
    }
  }
  
  /// 处理接收到的电脑剪贴板内容
  Future<void> _onClipboardReceived(ClipboardContent content) async {
    final success = await MobileClipboardHelper.writeContent(content);
    
    if (success) {
      if (content.type == ClipboardDataType.text) {
        _showSnackBar('已接收文本到剪贴板');
      } else {
        _showSnackBar('已接收图片(已保存到临时文件)');
      }
    } else {
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
    
    // 用 SnackBar 通知搜索结果
    if (_devices.isEmpty) {
      _showSnackBar('未发现设备');
    } else {
      _showSnackBar('发现 ${_devices.length} 个设备');
    }
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
    });

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
  
  /// 发送控制指令到电脑
  Future<void> _sendCommand(String command, String label) async {
    if (_selectedDevice == null) {
      _showSnackBar('请先选择目标设备');
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
        final password = await _showPasswordDialog();
        if (password == null) return;
        passwordHash = AuthService.hashPassword(password);
        _devicePasswords[deviceKey] = passwordHash;
      }
    }
    
    final result = await _socketService.sendMessage(
      _selectedDevice!.ip,
      _selectedDevice!.port,
      command,
      passwordHash: passwordHash,
    );
    
    if (result.success) {
      _showSnackBar('已发送: $label');
    } else {
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
  
  /// 构建方向键按钮
  Widget _buildArrowButton(IconData icon, String command, String label) {
    return SizedBox(
      width: 48,
      height: 48,
      child: OutlinedButton(
        onPressed: _selectedDevice == null ? null : () => _sendCommand(command, label),
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Icon(icon, size: 24),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 通过 MediaQuery 判断键盘是否可见，避免 setState 导致输入框失焦
    final isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    
    // 判断是否显示悬浮发送按钮：键盘可见 + 有选中设备 + 输入框有内容
    final showFloatingButton = isKeyboardVisible && 
        _selectedDevice != null && 
        _textController.text.trim().isNotEmpty;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('LAN Clip - 发送端'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // 触摸板入口按钮
          IconButton(
            icon: const Icon(Icons.touch_app),
            tooltip: '触摸板',
            onPressed: _selectedDevice == null ? null : _openTouchpad,
          ),
        ],
      ),
      // 悬浮发送按钮 - 键盘弹出时显示
      floatingActionButton: showFloatingButton
          ? FloatingActionButton.extended(
              onPressed: _isSending ? null : _sendContent,
              icon: _isSending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send),
              label: Text(_isSending ? '发送中' : '发送'),
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 设备选择区域 - 键盘弹出时隐藏
            if (!isKeyboardVisible)
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
            if (!isKeyboardVisible) const SizedBox(height: 12),
            
            // 自动发送设置 - 键盘弹出时隐藏
            if (!isKeyboardVisible)
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('停止输入后自动发送'),
                          Switch(
                            value: _autoSendEnabled,
                            onChanged: (value) {
                              setState(() {
                                _autoSendEnabled = value;
                                if (!value) {
                                  _cancelAutoSendTimer();
                                }
                              });
                              _saveAutoSendSettings();
                            },
                          ),
                        ],
                      ),
                      // 延迟时间设置（仅在启用时显示）
                      if (_autoSendEnabled) ...[
                        Row(
                          children: [
                            const Text('延迟时间: '),
                            Expanded(
                              child: Slider(
                                value: _autoSendDelay.toDouble(),
                                min: 1,
                                max: 10,
                                divisions: 9,
                                label: '$_autoSendDelay 秒',
                                onChanged: (value) {
                                  setState(() {
                                    _autoSendDelay = value.round();
                                  });
                                  _cancelAutoSendTimer();
                                },
                                onChangeEnd: (value) {
                                  _saveAutoSendSettings();
                                },
                              ),
                            ),
                            Text('$_autoSendDelay 秒'),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            if (!isKeyboardVisible) const SizedBox(height: 12),
            
            // 接收电脑剪贴板设置 - 键盘弹出时隐藏
            if (!isKeyboardVisible)
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('接收电脑剪贴板'),
                            Text(
                              _receiveFromPc 
                                  ? '已启用 (监听端口: $_syncPort)' 
                                  : '关闭时无法接收电脑复制的内容',
                              style: TextStyle(
                                color: _receiveFromPc ? Colors.green : Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _receiveFromPc,
                        onChanged: _setReceiveFromPc,
                      ),
                    ],
                  ),
                ),
              ),
            if (!isKeyboardVisible) const SizedBox(height: 12),
            
            // 输入区域
            Expanded(
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
            
            // 键盘弹出时隐藏下方的快捷按钮，只保留倒计时提示
            if (!isKeyboardVisible) ...[
              const SizedBox(height: 12),
              
              // 快捷操作按钮 - 第一行
              Row(
                children: [
                  Expanded(
                    child: _buildCommandButton(
                      icon: Icons.backspace_outlined,
                      label: '退格',
                      command: cmdBackspace,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _buildCommandButton(
                      icon: Icons.space_bar,
                      label: '空格',
                      command: cmdSpace,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _buildCommandButton(
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
            ],
            
            // 自动发送倒计时提示
            if (_countdownSeconds > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
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
                      '$_countdownSeconds 秒后自动发送...',
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
            
            // 发送按钮 - 键盘弹出时隐藏（由悬浮按钮替代）
            if (!isKeyboardVisible)
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
