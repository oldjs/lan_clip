import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device.dart';
import '../services/socket_service.dart';

/// 触摸板屏幕 - 手机端控制电脑鼠标
class TouchpadScreen extends StatefulWidget {
  final Device device;
  final String? passwordHash;

  const TouchpadScreen({
    super.key,
    required this.device,
    this.passwordHash,
  });

  @override
  State<TouchpadScreen> createState() => _TouchpadScreenState();
}

class _TouchpadScreenState extends State<TouchpadScreen> {
  final SocketService _socketService = SocketService();
  double _sensitivity = 1.5;
  bool _isTouching = false;
  
  // 累积未发送的偏移量，确保精度
  double _accDx = 0;
  double _accDy = 0;

  // 双指滑动及长按拖拽跟踪
  final Map<int, Offset> _pointers = {};
  double? _lastScrollY;
  Offset? _lastLongPressPosition;
  
  // 滚动按钮连续触发定时器
  Timer? _scrollTimer;

  @override
  void initState() {
    super.initState();
    _loadSensitivity();
  }

  /// 加载灵敏度配置
  Future<void> _loadSensitivity() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _sensitivity = prefs.getDouble('touchpad_sensitivity') ?? 1.5;
    });
  }

  /// 保存灵敏度配置
  Future<void> _saveSensitivity(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('touchpad_sensitivity', value);
  }

  /// 发送鼠标指令
  void _sendCommand(String command) {
    _socketService.sendMessage(
      widget.device.ip,
      widget.device.port,
      command,
      passwordHash: widget.passwordHash,
    );
  }

  /// 处理移动指令，累积小数部分
  void _sendMoveCommand(double dx, double dy) {
    _accDx += dx * _sensitivity;
    _accDy += dy * _sensitivity;

    int moveX = _accDx.toInt();
    int moveY = _accDy.toInt();

    if (moveX != 0 || moveY != 0) {
      _sendCommand('CMD:MOUSE_MOVE:$moveX:$moveY');
      _accDx -= moveX;
      _accDy -= moveY;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        title: const Text('触摸板', style: TextStyle(fontWeight: FontWeight.w300)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          _buildSensitivitySlider(),
          Expanded(child: _buildTouchpadArea()),
          _buildBottomButtons(),
        ],
      ),
    );
  }

  /// 灵敏度调节栏
  Widget _buildSensitivitySlider() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('灵敏度', style: TextStyle(color: Colors.white70)),
              Text('${_sensitivity.toStringAsFixed(1)}x',
                  style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Colors.cyanAccent,
              inactiveTrackColor: Colors.white12,
              thumbColor: Colors.cyanAccent,
              overlayColor: Colors.cyanAccent.withOpacity(0.2),
            ),
            child: Slider(
              value: _sensitivity,
              min: 0.5,
              max: 3.0,
              onChanged: (value) {
                setState(() => _sensitivity = value);
              },
              onChangeEnd: _saveSensitivity,
            ),
          ),
        ],
      ),
    );
  }

  /// 核心触摸板区域
  Widget _buildTouchpadArea() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isTouching ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12, width: 1),
      ),
      child: Listener(
        onPointerDown: (e) {
          setState(() {
            _isTouching = true;
            _pointers[e.pointer] = e.position;
          });
        },
        onPointerMove: (e) {
          _pointers[e.pointer] = e.position;
          // 处理双指滚动
          if (_pointers.length == 2) {
            double currentY = 0;
            for (var pos in _pointers.values) {
              currentY += pos.dy;
            }
            currentY /= 2;

            if (_lastScrollY != null) {
              // 向上滑动 (currentY < lastScrollY) 应该发送正数 delta (页面向上滚)
              int delta = ((_lastScrollY! - currentY) * 0.3).toInt();
              if (delta != 0) {
                _sendCommand('CMD:MOUSE_SCROLL:$delta');
              }
            }
            _lastScrollY = currentY;
          }
        },
        onPointerUp: (e) {
          setState(() {
            _pointers.remove(e.pointer);
            if (_pointers.isEmpty) {
              _isTouching = false;
              _lastScrollY = null;
            }
          });
        },
        onPointerCancel: (e) {
          setState(() {
            _pointers.remove(e.pointer);
            if (_pointers.isEmpty) {
              _isTouching = false;
              _lastScrollY = null;
            }
          });
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (details) {
            // 仅单指滑动时处理移动
            if (_pointers.length <= 1) {
              _sendMoveCommand(details.delta.dx, details.delta.dy);
            }
          },
          onTap: () => _sendCommand('CMD:MOUSE_LEFT_CLICK'),
          onLongPressStart: (details) {
            _sendCommand('CMD:MOUSE_LEFT_DOWN');
            _lastLongPressPosition = details.localPosition;
          },
          onLongPressMoveUpdate: (details) {
            if (_lastLongPressPosition != null) {
              final delta = details.localPosition - _lastLongPressPosition!;
              _sendMoveCommand(delta.dx, delta.dy);
              _lastLongPressPosition = details.localPosition;
            }
          },
          onLongPressEnd: (_) {
            _sendCommand('CMD:MOUSE_LEFT_UP');
            _lastLongPressPosition = null;
          },
          child: const Center(
            child: Icon(Icons.touch_app_outlined, color: Colors.white10, size: 80),
          ),
        ),
      ),
    );
  }

  /// 底部功能按钮
  Widget _buildBottomButtons() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
      height: 140,
      child: Row(
        children: [
          // 左键
          Expanded(
            flex: 2,
            child: _buildActionButton(
              '左键',
              () => _sendCommand('CMD:MOUSE_LEFT_CLICK'),
              onLongPress: () => _sendCommand('CMD:MOUSE_LEFT_DOWN'),
              onLongPressEnd: () => _sendCommand('CMD:MOUSE_LEFT_UP'),
            ),
          ),
          const SizedBox(width: 12),
          // 滚轮上下按钮（触碰即触发）
          Expanded(
            flex: 1,
            child: Column(
              children: [
                Expanded(child: _buildScrollButton(isUp: true)),
                const SizedBox(height: 8),
                Expanded(child: _buildScrollButton(isUp: false)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 右键
          Expanded(
            flex: 2,
            child: _buildActionButton(
              '右键',
              () => _sendCommand('CMD:MOUSE_RIGHT_CLICK'),
            ),
          ),
        ],
      ),
    );
  }

  /// 通用功能按钮构建
  Widget _buildActionButton(String label, VoidCallback onTap, 
      {VoidCallback? onLongPress, VoidCallback? onLongPressEnd}) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      onLongPressUp: onLongPressEnd,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white.withOpacity(0.1), Colors.white.withOpacity(0.05)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        alignment: Alignment.center,
        child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 16)),
      ),
    );
  }
  
  /// 滚动按钮（触碰即触发，持续滚动）
  Widget _buildScrollButton({required bool isUp}) {
    return Listener(
      onPointerDown: (_) {
        // 触碰立即滚动一次，然后每 80ms 连续滚动
        final delta = isUp ? 3 : -3;
        _sendCommand('CMD:MOUSE_SCROLL:$delta');
        _scrollTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
          _sendCommand('CMD:MOUSE_SCROLL:$delta');
        });
      },
      onPointerUp: (_) {
        _scrollTimer?.cancel();
        _scrollTimer = null;
      },
      onPointerCancel: (_) {
        _scrollTimer?.cancel();
        _scrollTimer = null;
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        alignment: Alignment.center,
        child: Icon(
          isUp ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
          color: Colors.white38,
          size: 28,
        ),
      ),
    );
  }
}
