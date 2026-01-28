import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cryptography/cryptography.dart';

import '../models/device.dart';
import '../models/remote_request.dart';
import '../services/socket_service.dart';

// 设置存储键
const String _remoteScreenIntervalKey = 'remote_screen_interval';
const String _remoteScreenQualityKey = 'remote_screen_quality';
const String _remoteScreenScaleKey = 'remote_screen_scale';

/// 远程画面悬浮窗
class RemoteScreenOverlay extends StatefulWidget {
  final Device device;
  final String? passwordHash;
  final SecretKey? encryptionKey;
  final bool encryptionEnabled;

  const RemoteScreenOverlay({
    super.key,
    required this.device,
    this.passwordHash,
    this.encryptionKey,
    this.encryptionEnabled = false,
  });

  @override
  State<RemoteScreenOverlay> createState() => _RemoteScreenOverlayState();
}

class _RemoteScreenOverlayState extends State<RemoteScreenOverlay> with WidgetsBindingObserver {
  final _socketService = SocketService();
  
  // 悬浮窗状态
  bool _isExpanded = false;
  bool _isLoading = false;
  Uint8List? _imageData;
  int _cursorX = 0;
  int _cursorY = 0;
  int _screenWidth = 0;
  int _screenHeight = 0;
  
  // 位置
  double _posX = 20;
  double _posY = 100;
  
  // 设置
  int _captureInterval = 50; // ms
  int _quality = 50;
  double _scale = 0.5;
  
  // 定时器
  Timer? _captureTimer;
  bool _isCapturing = false;
  
  // 展开时的尺寸
  double _overlayWidth = 300;
  double _overlayHeight = 200;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    if (widget.encryptionEnabled && widget.encryptionKey != null) {
      _socketService.setEncryption(enabled: true, key: widget.encryptionKey);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopCapture();
    _socketService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 应用进入后台时停止截图
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _stopCapture();
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _captureInterval = prefs.getInt(_remoteScreenIntervalKey) ?? 50;
      _quality = prefs.getInt(_remoteScreenQualityKey) ?? 50;
      _scale = prefs.getDouble(_remoteScreenScaleKey) ?? 0.5;
    });
  }

  void _startCapture() {
    if (_isCapturing) return;
    _isCapturing = true;
    
    // 立即请求一次
    _requestCapture();
    
    // 设置定时器持续请求
    _captureTimer = Timer.periodic(Duration(milliseconds: _captureInterval), (_) {
      if (_isExpanded && _isCapturing) {
        _requestCapture();
      }
    });
  }

  void _stopCapture() {
    _isCapturing = false;
    _captureTimer?.cancel();
    _captureTimer = null;
  }

  Future<void> _requestCapture() async {
    if (_isLoading || !_isExpanded) return;
    
    try {
      final request = RemoteRequest(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        action: 'screen_capture',
        payload: {
          'quality': _quality,
          'scale': _scale,
        },
      );

      final response = await _socketService.sendRequest(
        widget.device.ip,
        widget.device.port,
        request,
        passwordHash: widget.passwordHash,
        timeout: const Duration(seconds: 5),
      );

      if (response != null && response.ok && response.data != null && mounted && _isExpanded) {
        final data = response.data!;
        // 图像数据可能是List<int>或base64字符串
        Uint8List? imageBytes;
        if (data['image'] is List) {
          imageBytes = Uint8List.fromList(List<int>.from(data['image']));
        } else if (data['image'] is String) {
          imageBytes = base64Decode(data['image']);
        }
        
        if (imageBytes != null) {
          setState(() {
            _imageData = imageBytes;
            _cursorX = data['cursorX'] ?? 0;
            _cursorY = data['cursorY'] ?? 0;
            _screenWidth = data['width'] ?? 0;
            _screenHeight = data['height'] ?? 0;
          });
        }
      }
    } catch (e) {
      // 静默处理错误，继续下一次请求
    }
  }

  void _toggleExpand() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _startCapture();
      } else {
        _stopCapture();
        _imageData = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    
    // 确保悬浮窗在屏幕范围内
    _posX = _posX.clamp(0, screenSize.width - (_isExpanded ? _overlayWidth : 56));
    _posY = _posY.clamp(0, screenSize.height - (_isExpanded ? _overlayHeight + 40 : 56));

    return Positioned(
      left: _posX,
      top: _posY,
      child: Material(
        color: Colors.transparent,
        child: _isExpanded ? _buildExpandedOverlay() : _buildCollapsedOverlay(),
      ),
    );
  }

  Widget _buildCollapsedOverlay() {
    return GestureDetector(
      onPanUpdate: (details) {
        setState(() {
          _posX += details.delta.dx;
          _posY += details.delta.dy;
        });
      },
      onTap: _toggleExpand,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.blue.shade700,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(
          Icons.desktop_windows,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }

  Widget _buildExpandedOverlay() {
    return Container(
      width: _overlayWidth,
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题栏 - 可拖动
          GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _posX += details.delta.dx;
                _posY += details.delta.dy;
              });
            },
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: Colors.blue.shade700,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  const Icon(Icons.drag_indicator, color: Colors.white70, size: 18),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text(
                      '远程画面',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  // 调整大小按钮
                  IconButton(
                    icon: Icon(
                      _overlayWidth > 250 ? Icons.fullscreen_exit : Icons.fullscreen,
                      color: Colors.white70,
                      size: 18,
                    ),
                    onPressed: () {
                      setState(() {
                        if (_overlayWidth > 250) {
                          _overlayWidth = 200;
                          _overlayHeight = 130;
                        } else {
                          _overlayWidth = 350;
                          _overlayHeight = 230;
                        }
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                  // 关闭按钮
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                    onPressed: _toggleExpand,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
          // 画面内容
          Container(
            height: _overlayHeight,
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
              child: _buildScreenContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScreenContent() {
    if (_imageData == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white54,
            ),
            SizedBox(height: 8),
            Text(
              '正在连接...',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // 屏幕画面
        Image.memory(
          _imageData!,
          fit: BoxFit.contain,
          gaplessPlayback: true, // 防止闪烁
        ),
        // 这里不再单独绘制光标，因为PC端已经把光标绘制到截图中了
      ],
    );
  }
}

/// 悬浮窗管理器 - 用于在页面上显示悬浮窗
class RemoteScreenOverlayManager {
  static OverlayEntry? _overlayEntry;
  static bool _isShowing = false;

  static bool get isShowing => _isShowing;

  static void show(
    BuildContext context, {
    required Device device,
    String? passwordHash,
    SecretKey? encryptionKey,
    bool encryptionEnabled = false,
  }) {
    if (_isShowing) return;

    _overlayEntry = OverlayEntry(
      builder: (context) => RemoteScreenOverlay(
        device: device,
        passwordHash: passwordHash,
        encryptionKey: encryptionKey,
        encryptionEnabled: encryptionEnabled,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
    _isShowing = true;
  }

  static void hide() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _isShowing = false;
  }

  static void toggle(
    BuildContext context, {
    required Device device,
    String? passwordHash,
    SecretKey? encryptionKey,
    bool encryptionEnabled = false,
  }) {
    if (_isShowing) {
      hide();
    } else {
      show(
        context,
        device: device,
        passwordHash: passwordHash,
        encryptionKey: encryptionKey,
        encryptionEnabled: encryptionEnabled,
      );
    }
  }
}
