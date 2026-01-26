// ignore_for_file: constant_identifier_names

import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// ==================== INPUT 类型常量 ====================
const int INPUT_MOUSE = 0;
const int INPUT_KEYBOARD = 1;

// ==================== 鼠标事件标志位 ====================
const int MOUSEEVENTF_MOVE = 0x0001;
const int MOUSEEVENTF_LEFTDOWN = 0x0002;
const int MOUSEEVENTF_LEFTUP = 0x0004;
const int MOUSEEVENTF_RIGHTDOWN = 0x0008;
const int MOUSEEVENTF_RIGHTUP = 0x0010;
const int MOUSEEVENTF_MIDDLEDOWN = 0x0020;
const int MOUSEEVENTF_MIDDLEUP = 0x0040;
const int MOUSEEVENTF_WHEEL = 0x0800;
const int MOUSEEVENTF_HWHEEL = 0x1000;
const int MOUSEEVENTF_ABSOLUTE = 0x8000;

const int WHEEL_DELTA = 120;

// ==================== FFI 结构体定义 ====================

/// MOUSEINPUT 结构体
/// https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-mouseinput
base class MOUSEINPUT extends Struct {
  @Int32()
  external int dx;
  @Int32()
  external int dy;
  @Int32()
  external int mouseData;
  @Uint32()
  external int dwFlags;
  @Uint32()
  external int time;
  @IntPtr()
  external int dwExtraInfo;
}

/// KEYBDINPUT 结构体 (占位，用于 Union 对齐)
base class KEYBDINPUT extends Struct {
  @Uint16()
  external int wVk;
  @Uint16()
  external int wScan;
  @Uint32()
  external int dwFlags;
  @Uint32()
  external int time;
  @IntPtr()
  external int dwExtraInfo;
}

/// HARDWAREINPUT 结构体 (占位，用于 Union 对齐)
base class HARDWAREINPUT extends Struct {
  @Uint32()
  external int uMsg;
  @Uint16()
  external int wParamL;
  @Uint16()
  external int wParamH;
}

/// INPUT 结构体中的 Union
/// 三种输入类型共用内存空间
sealed class InputUnion extends Union {
  external MOUSEINPUT mi;
  external KEYBDINPUT ki;
  external HARDWAREINPUT hi;
}

/// INPUT 结构体
/// https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-input
base class INPUT extends Struct {
  @Uint32()
  external int type;
  external InputUnion u;
}

// ==================== SendInput 函数签名 ====================

typedef SendInputNative = Uint32 Function(
  Uint32 cInputs,
  Pointer<INPUT> pInputs,
  Int32 cbSize,
);

typedef SendInputDart = int Function(
  int cInputs,
  Pointer<INPUT> pInputs,
  int cbSize,
);

/// Windows 鼠标控制服务
/// 使用 SendInput API (比 mouse_event 更可靠)
class MouseService {
  // 单例模式
  static final MouseService _instance = MouseService._internal();
  factory MouseService() => _instance;
  MouseService._internal() {
    _init();
  }

  SendInputDart? _sendInput;
  bool _initialized = false;

  /// 初始化 FFI 绑定
  void _init() {
    if (!Platform.isWindows) return;
    try {
      final user32 = DynamicLibrary.open('user32.dll');
      _sendInput = user32.lookupFunction<SendInputNative, SendInputDart>('SendInput');
      _initialized = true;
    } catch (e) {
      _initialized = false;
    }
  }

  /// 发送鼠标输入事件
  /// 返回成功发送的事件数量
  int _sendMouseInput({
    int dx = 0, 
    int dy = 0, 
    int mouseData = 0, 
    required int dwFlags,
  }) {
    if (!_initialized || _sendInput == null) return 0;
    
    final input = calloc<INPUT>();
    try {
      input.ref.type = INPUT_MOUSE;
      input.ref.u.mi.dx = dx;
      input.ref.u.mi.dy = dy;
      input.ref.u.mi.mouseData = mouseData;
      input.ref.u.mi.dwFlags = dwFlags;
      input.ref.u.mi.time = 0;
      input.ref.u.mi.dwExtraInfo = 0;
      
      return _sendInput!(1, input, sizeOf<INPUT>());
    } catch (e) {
      return 0;
    } finally {
      calloc.free(input);
    }
  }

  /// 相对移动鼠标
  void move(int dx, int dy) {
    _sendMouseInput(dx: dx, dy: dy, dwFlags: MOUSEEVENTF_MOVE);
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
    _sendMouseInput(dwFlags: MOUSEEVENTF_LEFTDOWN);
  }

  /// 左键释放（用于拖拽结束）
  void leftUp() {
    _sendMouseInput(dwFlags: MOUSEEVENTF_LEFTUP);
  }

  /// 右键按下
  void rightDown() {
    _sendMouseInput(dwFlags: MOUSEEVENTF_RIGHTDOWN);
  }

  /// 右键释放
  void rightUp() {
    _sendMouseInput(dwFlags: MOUSEEVENTF_RIGHTUP);
  }

  /// 中键按下
  void middleDown() {
    _sendMouseInput(dwFlags: MOUSEEVENTF_MIDDLEDOWN);
  }

  /// 中键释放
  void middleUp() {
    _sendMouseInput(dwFlags: MOUSEEVENTF_MIDDLEUP);
  }

  /// 滚轮滚动，delta 正数向上，负数向下
  void scroll(int delta) {
    _sendMouseInput(
      mouseData: delta * WHEEL_DELTA, 
      dwFlags: MOUSEEVENTF_WHEEL,
    );
  }
  
  /// 水平滚轮滚动，delta 正数向右，负数向左
  void scrollH(int delta) {
    _sendMouseInput(
      mouseData: delta * WHEEL_DELTA, 
      dwFlags: MOUSEEVENTF_HWHEEL,
    );
  }
}
