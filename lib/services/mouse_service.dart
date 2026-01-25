// ignore_for_file: constant_identifier_names

import 'dart:ffi';
import 'dart:io';

// Windows mouse_event 标志位
const int MOUSEEVENTF_MOVE = 0x0001;
const int MOUSEEVENTF_LEFTDOWN = 0x0002;
const int MOUSEEVENTF_LEFTUP = 0x0004;
const int MOUSEEVENTF_RIGHTDOWN = 0x0008;
const int MOUSEEVENTF_RIGHTUP = 0x0010;
const int MOUSEEVENTF_WHEEL = 0x0800;
const int MOUSEEVENTF_ABSOLUTE = 0x8000;
const int WHEEL_DELTA = 120;

// 定义 mouse_event 的 FFI 签名
// void mouse_event(DWORD dwFlags, DWORD dx, DWORD dy, DWORD dwData, ULONG_PTR dwExtraInfo)
typedef MouseEventNative = Void Function(
  Uint32 dwFlags,
  Uint32 dx,
  Uint32 dy,
  Uint32 dwData,
  IntPtr dwExtraInfo,
);

typedef MouseEventDart = void Function(
  int dwFlags,
  int dx,
  int dy,
  int dwData,
  int dwExtraInfo,
);

/// Windows 鼠标控制服务
class MouseService {
  // 单例模式
  static final MouseService _instance = MouseService._internal();
  factory MouseService() => _instance;
  MouseService._internal() {
    _init();
  }

  MouseEventDart? _mouseEvent;
  bool _initialized = false;

  /// 初始化 FFI 绑定
  void _init() {
    if (!Platform.isWindows) return;
    try {
      final user32 = DynamicLibrary.open('user32.dll');
      _mouseEvent = user32
          .lookupFunction<MouseEventNative, MouseEventDart>('mouse_event');
      _initialized = true;
    } catch (e) {
      // 在非 Windows 环境或加载失败时静默处理
      _initialized = false;
    }
  }

  /// 发送鼠标事件的统一封装
  void _sendEvent(int flags, {int dx = 0, int dy = 0, int data = 0}) {
    if (!_initialized || _mouseEvent == null) return;
    try {
      _mouseEvent!(flags, dx, dy, data, 0);
    } catch (e) {
      // 捕获可能的调用异常
    }
  }

  /// 相对移动鼠标
  void move(int dx, int dy) {
    _sendEvent(MOUSEEVENTF_MOVE, dx: dx, dy: dy);
  }

  /// 左键单击
  void leftClick() {
    leftDown();
    leftUp();
  }

  /// 右键单击
  void rightClick() {
    rightDown();
    rightUp();
  }

  /// 左键按下（用于拖拽开始）
  void leftDown() {
    _sendEvent(MOUSEEVENTF_LEFTDOWN);
  }

  /// 左键释放（用于拖拽结束）
  void leftUp() {
    _sendEvent(MOUSEEVENTF_LEFTUP);
  }

  /// 右键按下
  void rightDown() {
    _sendEvent(MOUSEEVENTF_RIGHTDOWN);
  }

  /// 右键释放
  void rightUp() {
    _sendEvent(MOUSEEVENTF_RIGHTUP);
  }

  /// 滚轮滚动，delta 正数向上，负数向下
  void scroll(int delta) {
    // dwData 为滚动量，正数向前（远离用户），负数向后（靠近用户）
    _sendEvent(MOUSEEVENTF_WHEEL, data: delta * WHEEL_DELTA);
  }
}
