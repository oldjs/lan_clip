import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device.dart';
import '../services/socket_service.dart';

// 自动发送设置的存储键（与主页面共享）
const String _autoSendEnabledKey = 'auto_send_enabled';
const String _autoSendDelayKey = 'auto_send_delay';

/// 简洁输入页面 - 只有输入框和发送按钮，适合键盘兼容性问题时使用
class SimpleInputScreen extends StatefulWidget {
  final Device device;
  final String? passwordHash;

  const SimpleInputScreen({
    super.key,
    required this.device,
    this.passwordHash,
  });

  @override
  State<SimpleInputScreen> createState() => _SimpleInputScreenState();
}

class _SimpleInputScreenState extends State<SimpleInputScreen> {
  final _textController = TextEditingController();
  final _socketService = SocketService();
  final _inputFocusNode = FocusNode();
  
  bool _isSending = false;
  
  // 自动发送相关状态
  bool _autoSendEnabled = false;
  int _autoSendDelay = 3;
  Timer? _autoSendTimer;
  int _countdownSeconds = 0;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _textController.addListener(_onTextChanged);
    
    // 自动聚焦输入框
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inputFocusNode.requestFocus();
    });
  }

  /// 加载自动发送设置
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoSendEnabled = prefs.getBool(_autoSendEnabledKey) ?? false;
      _autoSendDelay = prefs.getInt(_autoSendDelayKey) ?? 3;
    });
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _inputFocusNode.dispose();
    _socketService.dispose();
    _cancelAutoSendTimer();
    super.dispose();
  }

  /// 输入变化时的回调 - 触发自动发送
  void _onTextChanged() {
    if (!_autoSendEnabled) return;
    
    _cancelAutoSendTimer();
    
    final content = _textController.text.trim();
    if (content.isEmpty || _isSending) return;
    
    // 启动倒计时
    _countdownSeconds = _autoSendDelay;
    setState(() {});
    
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _countdownSeconds--;
      });
      if (_countdownSeconds <= 0) {
        timer.cancel();
      }
    });
    
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

  /// 发送内容
  Future<void> _sendContent() async {
    final content = _textController.text.trim();
    if (content.isEmpty) {
      _showSnackBar('请输入要发送的内容');
      return;
    }

    setState(() {
      _isSending = true;
    });

    final result = await _socketService.sendMessage(
      widget.device.ip,
      widget.device.port,
      content,
      passwordHash: widget.passwordHash,
    );

    setState(() {
      _isSending = false;
    });

    if (result.success) {
      _textController.clear();
      _showSnackBar('已发送');
    } else {
      _showSnackBar('发送失败: ${result.error ?? "请检查网络连接"}');
    }
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
        title: Text('发送到 ${widget.device.name}'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 自动发送倒计时提示
            if (_countdownSeconds > 0)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                color: Colors.blue.shade50,
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
            
            // 输入框 - 占据大部分空间
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: _textController,
                  focusNode: _inputFocusNode,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: InputDecoration(
                    hintText: '输入要发送的内容...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                ),
              ),
            ),
            
            // 底部发送按钮
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _isSending ? null : _sendContent,
                  icon: _isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: Text(_isSending ? '发送中...' : '发送'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
