import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device.dart';
import '../services/socket_service.dart';
import '../services/clipboard_service.dart' show 
    cmdCopy, cmdPaste, cmdCut, cmdUndo, cmdRedo,
    cmdTab, cmdEsc, cmdHome, cmdDelete,
    cmdSave, cmdNew, cmdOpen, cmdClose, cmdFind, cmdQuickOpen,
    cmdWin, cmdWinD, cmdWinE, cmdAltTab, cmdAltF4;

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
  bool _shortcutsExpanded = false;  // 快捷键是否展开
  
  // 累积未发送的偏移量，确保精度
  double _accDx = 0;
  double _accDy = 0;

  // 双指滑动及长按拖拽跟踪
  final Map<int, Offset> _pointers = {};
  double? _lastScrollY;
  Offset? _lastLongPressPosition;
  
  // 滚动按钮连续触发定时器
  Timer? _scrollTimer;

  // 快捷键分组定义
  static const List<_ShortcutItem> _editShortcuts = [
    _ShortcutItem('复制', cmdCopy, Icons.copy),
    _ShortcutItem('粘贴', cmdPaste, Icons.paste),
    _ShortcutItem('剪切', cmdCut, Icons.content_cut),
    _ShortcutItem('撤销', cmdUndo, Icons.undo),
    _ShortcutItem('重做', cmdRedo, Icons.redo),
  ];

  static const List<_ShortcutItem> _navShortcuts = [
    _ShortcutItem('Tab', cmdTab, Icons.keyboard_tab),
    _ShortcutItem('Esc', cmdEsc, Icons.close),
    _ShortcutItem('Win', cmdWin, Icons.window),
    _ShortcutItem('Ctrl+P', cmdQuickOpen, Icons.search),
    _ShortcutItem('Ctrl+S', cmdSave, Icons.save),
  ];

  static const List<_ShortcutItem> _fileShortcuts = [
    _ShortcutItem('Ctrl+W', cmdClose, Icons.close_fullscreen),
    _ShortcutItem('Ctrl+N', cmdNew, Icons.add),
    _ShortcutItem('Ctrl+O', cmdOpen, Icons.folder_open),
    _ShortcutItem('Ctrl+F', cmdFind, Icons.find_in_page),
    _ShortcutItem('Delete', cmdDelete, Icons.backspace_outlined),
  ];

  static const List<_ShortcutItem> _sysShortcuts = [
    _ShortcutItem('Win+D', cmdWinD, Icons.desktop_windows),
    _ShortcutItem('Win+E', cmdWinE, Icons.folder),
    _ShortcutItem('Alt+Tab', cmdAltTab, Icons.swap_horiz),
    _ShortcutItem('Alt+F4', cmdAltF4, Icons.power_settings_new),
    _ShortcutItem('Home', cmdHome, Icons.first_page),
  ];

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
      _shortcutsExpanded = prefs.getBool('shortcuts_expanded') ?? false;
    });
  }

  /// 保存快捷键展开状态
  Future<void> _saveShortcutsExpanded(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('shortcuts_expanded', value);
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
          _buildSensitivitySlider(),      // 瘦身后的灵敏度条
          Expanded(child: _buildTouchpadArea()),  // 触摸板
          _buildMouseButtons(),           // 鼠标按钮
          _buildShortcutsSection(),       // 可折叠快捷键区
        ],
      ),
    );
  }

  /// 灵敏度调节栏
  Widget _buildSensitivitySlider() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          const Text('灵敏度', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(width: 8),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: Colors.cyanAccent,
                inactiveTrackColor: Colors.white12,
                thumbColor: Colors.cyanAccent,
                overlayColor: Colors.cyanAccent.withOpacity(0.2),
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
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
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 32,
            child: Text('${_sensitivity.toStringAsFixed(1)}x',
                style: const TextStyle(color: Colors.cyanAccent, fontSize: 13)),
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

  /// 鼠标控制按钮
  Widget _buildMouseButtons() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      height: 80,
      child: Row(
        children: [
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
          Expanded(
            flex: 1,
            child: Column(
              children: [
                Expanded(child: _buildScrollButton(isUp: true)),
                const SizedBox(height: 6),
                Expanded(child: _buildScrollButton(isUp: false)),
              ],
            ),
          ),
          const SizedBox(width: 12),
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

  /// 可折叠快捷键区
  Widget _buildShortcutsSection() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题栏 + 展开/收起按钮
          GestureDetector(
            onTap: () {
              setState(() => _shortcutsExpanded = !_shortcutsExpanded);
              _saveShortcutsExpanded(_shortcutsExpanded);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              color: Colors.transparent, // 扩大点击区域
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('快捷键', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  Icon(
                    _shortcutsExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: Colors.white38,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          // 快捷键按钮区
          AnimatedCrossFade(
            firstChild: _buildShortcutRow(_editShortcuts),  // 折叠时只显示编辑行
            secondChild: _buildAllShortcutRows(),            // 展开时显示全部
            crossFadeState: _shortcutsExpanded 
                ? CrossFadeState.showSecond 
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  /// 构建单行快捷键
  Widget _buildShortcutRow(List<_ShortcutItem> items) {
    return SizedBox(
      height: 40,
      child: Row(
        children: items.asMap().entries.map((entry) {
          final item = entry.value;
          final isLast = entry.key == items.length - 1;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: isLast ? 0 : 6),
              child: _buildSmallButton(item.label, item.command, item.icon),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 构建全部快捷键行（展开状态）
  Widget _buildAllShortcutRows() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildShortcutRow(_editShortcuts),
        const SizedBox(height: 6),
        _buildShortcutRow(_navShortcuts),
        const SizedBox(height: 6),
        _buildShortcutRow(_fileShortcuts),
        const SizedBox(height: 6),
        _buildShortcutRow(_sysShortcuts),
      ],
    );
  }

  /// 小型快捷键按钮（带图标）
  Widget _buildSmallButton(String label, String command, IconData icon) {
    return GestureDetector(
      onTap: () => _sendCommand(command),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.cyanAccent.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.cyanAccent, size: 16),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: Colors.cyanAccent,
                fontSize: 10,
              ),
            ),
          ],
        ),
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
        // 触碰立即滚动一次，然后每 150ms 连续滚动（delta=1 为最小滚动单位）
        final delta = isUp ? 1 : -1;
        _sendCommand('CMD:MOUSE_SCROLL:$delta');
        _scrollTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
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

/// 快捷键项数据
class _ShortcutItem {
  final String label;
  final String command;
  final IconData icon;
  const _ShortcutItem(this.label, this.command, this.icon);
}
