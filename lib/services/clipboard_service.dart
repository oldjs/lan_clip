import 'dart:io';
import 'package:flutter/services.dart';
import 'package:keypress_simulator/keypress_simulator.dart';
import 'mouse_service.dart';

// 控制指令前缀
const String cmdPrefix = 'CMD:';
const String cmdBackspace = '${cmdPrefix}BACKSPACE';
const String cmdSpace = '${cmdPrefix}SPACE';
const String cmdClear = '${cmdPrefix}CLEAR';
const String cmdEnter = '${cmdPrefix}ENTER';
const String cmdArrowUp = '${cmdPrefix}ARROW_UP';
const String cmdArrowDown = '${cmdPrefix}ARROW_DOWN';
const String cmdArrowLeft = '${cmdPrefix}ARROW_LEFT';
const String cmdArrowRight = '${cmdPrefix}ARROW_RIGHT';

// 鼠标控制指令
const String cmdMouseMove = '${cmdPrefix}MOUSE_MOVE';
const String cmdMouseLeftClick = '${cmdPrefix}MOUSE_LEFT_CLICK';
const String cmdMouseRightClick = '${cmdPrefix}MOUSE_RIGHT_CLICK';
const String cmdMouseLeftDown = '${cmdPrefix}MOUSE_LEFT_DOWN';
const String cmdMouseLeftUp = '${cmdPrefix}MOUSE_LEFT_UP';
const String cmdMouseScroll = '${cmdPrefix}MOUSE_SCROLL';

// 快捷键指令
const String cmdCopy = '${cmdPrefix}COPY';      // Ctrl+C
const String cmdPaste = '${cmdPrefix}PASTE';    // Ctrl+V
const String cmdCut = '${cmdPrefix}CUT';        // Ctrl+X
const String cmdUndo = '${cmdPrefix}UNDO';      // Ctrl+Z
const String cmdRedo = '${cmdPrefix}REDO';      // Ctrl+Y

/// 重试配置
const int _maxRetries = 3;           // 最大重试次数
const int _retryDelayMs = 30;        // 重试间隔(毫秒)
const int _keyPressDelayMs = 10;     // 按键之间的延迟(毫秒)

/// 剪切板服务
class ClipboardService {
  /// 判断是否为控制指令
  static bool isCommand(String message) {
    return message.startsWith(cmdPrefix);
  }
  
  /// 执行控制指令，返回操作描述
  static Future<String?> executeCommand(String command) async {
    if (!Platform.isWindows) return null;
    
    // 处理带参数的鼠标指令
    if (command.startsWith(cmdMouseMove)) {
      return _handleMouseMove(command);
    }
    if (command.startsWith(cmdMouseScroll)) {
      return _handleMouseScroll(command);
    }
    
    switch (command) {
      case cmdBackspace:
        await _simulateKeyWithRetry(PhysicalKeyboardKey.backspace);
        return '退格';
      case cmdSpace:
        await _simulateKeyWithRetry(PhysicalKeyboardKey.space);
        return '空格';
      case cmdClear:
        await _simulateClearWithRetry();
        return '清空';
      case cmdEnter:
        await _simulateKeyWithRetry(PhysicalKeyboardKey.enter);
        return '回车';
      case cmdArrowUp:
        await _simulateKeyWithRetry(PhysicalKeyboardKey.arrowUp);
        return '上移';
      case cmdArrowDown:
        await _simulateKeyWithRetry(PhysicalKeyboardKey.arrowDown);
        return '下移';
      case cmdArrowLeft:
        await _simulateKeyWithRetry(PhysicalKeyboardKey.arrowLeft);
        return '左移';
      case cmdArrowRight:
        await _simulateKeyWithRetry(PhysicalKeyboardKey.arrowRight);
        return '右移';
      // 鼠标控制指令（鼠标操作本身就很快，不需要重试）
      case cmdMouseLeftClick:
        MouseService().leftClick();
        return null;
      case cmdMouseRightClick:
        MouseService().rightClick();
        return null;
      case cmdMouseLeftDown:
        MouseService().leftDown();
        return null;
      case cmdMouseLeftUp:
        MouseService().leftUp();
        return null;
      // 快捷键指令
      case cmdCopy:
        await _simulateModifierKeyWithRetry(PhysicalKeyboardKey.keyC, ModifierKey.controlModifier);
        return null;
      case cmdPaste:
        await _simulateModifierKeyWithRetry(PhysicalKeyboardKey.keyV, ModifierKey.controlModifier);
        return null;
      case cmdCut:
        await _simulateModifierKeyWithRetry(PhysicalKeyboardKey.keyX, ModifierKey.controlModifier);
        return null;
      case cmdUndo:
        await _simulateModifierKeyWithRetry(PhysicalKeyboardKey.keyZ, ModifierKey.controlModifier);
        return null;
      case cmdRedo:
        await _simulateModifierKeyWithRetry(PhysicalKeyboardKey.keyY, ModifierKey.controlModifier);
        return null;
      default:
        return null;
    }
  }
  
  /// 处理鼠标移动指令: CMD:MOUSE_MOVE:dx:dy
  static String? _handleMouseMove(String command) {
    final parts = command.split(':');
    if (parts.length >= 4) {
      final dx = int.tryParse(parts[2]) ?? 0;
      final dy = int.tryParse(parts[3]) ?? 0;
      MouseService().move(dx, dy);
    }
    return null;
  }
  
  /// 处理滚轮指令: CMD:MOUSE_SCROLL:delta
  static String? _handleMouseScroll(String command) {
    final parts = command.split(':');
    if (parts.length >= 3) {
      final delta = int.tryParse(parts[2]) ?? 0;
      MouseService().scroll(delta);
    }
    return null;
  }
  
  // ==================== 带重试的按键模拟 ====================
  
  /// 带重试的单键模拟
  static Future<bool> _simulateKeyWithRetry(PhysicalKeyboardKey key) async {
    for (int i = 0; i < _maxRetries; i++) {
      try {
        await keyPressSimulator.simulateKeyDown(key, []);
        await Future.delayed(const Duration(milliseconds: _keyPressDelayMs));
        await keyPressSimulator.simulateKeyUp(key, []);
        return true;
      } catch (e) {
        if (i < _maxRetries - 1) {
          await Future.delayed(const Duration(milliseconds: _retryDelayMs));
        }
      }
    }
    return false;
  }
  
  /// 带重试的组合键模拟 (如 Ctrl+C)
  static Future<bool> _simulateModifierKeyWithRetry(
    PhysicalKeyboardKey key, 
    ModifierKey modifier,
  ) async {
    for (int i = 0; i < _maxRetries; i++) {
      try {
        await keyPressSimulator.simulateKeyDown(key, [modifier]);
        await Future.delayed(const Duration(milliseconds: _keyPressDelayMs));
        await keyPressSimulator.simulateKeyUp(key, [modifier]);
        return true;
      } catch (e) {
        if (i < _maxRetries - 1) {
          await Future.delayed(const Duration(milliseconds: _retryDelayMs));
        }
      }
    }
    return false;
  }
  
  /// 带重试的清空操作 (Ctrl+A, Delete)
  static Future<bool> _simulateClearWithRetry() async {
    for (int i = 0; i < _maxRetries; i++) {
      try {
        // Ctrl+A 全选
        await keyPressSimulator.simulateKeyDown(
          PhysicalKeyboardKey.keyA,
          [ModifierKey.controlModifier],
        );
        await Future.delayed(const Duration(milliseconds: _keyPressDelayMs));
        await keyPressSimulator.simulateKeyUp(
          PhysicalKeyboardKey.keyA,
          [ModifierKey.controlModifier],
        );
        // 短暂延迟确保全选完成
        await Future.delayed(const Duration(milliseconds: 30));
        // Delete 删除
        await keyPressSimulator.simulateKeyDown(PhysicalKeyboardKey.delete, []);
        await Future.delayed(const Duration(milliseconds: _keyPressDelayMs));
        await keyPressSimulator.simulateKeyUp(PhysicalKeyboardKey.delete, []);
        return true;
      } catch (e) {
        if (i < _maxRetries - 1) {
          await Future.delayed(const Duration(milliseconds: _retryDelayMs));
        }
      }
    }
    return false;
  }
  
  // ==================== 基础操作（保持向后兼容） ====================
  
  /// 模拟退格键
  static Future<bool> simulateBackspace() async {
    if (!Platform.isWindows) return false;
    return _simulateKeyWithRetry(PhysicalKeyboardKey.backspace);
  }
  
  /// 模拟空格键
  static Future<bool> simulateSpace() async {
    if (!Platform.isWindows) return false;
    return _simulateKeyWithRetry(PhysicalKeyboardKey.space);
  }
  
  /// 模拟 Ctrl+A 全选后 Delete 清空
  static Future<bool> simulateClear() async {
    if (!Platform.isWindows) return false;
    return _simulateClearWithRetry();
  }
  
  /// 模拟回车键
  static Future<bool> simulateEnter() async {
    if (!Platform.isWindows) return false;
    return _simulateKeyWithRetry(PhysicalKeyboardKey.enter);
  }
  
  /// 模拟方向键
  static Future<bool> simulateArrow(PhysicalKeyboardKey key) async {
    if (!Platform.isWindows) return false;
    return _simulateKeyWithRetry(key);
  }

  /// 复制文本到剪切板
  static Future<void> copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  /// 从剪切板读取文本
  static Future<String?> paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  }

  /// 模拟 Ctrl+C 复制操作（仅 Windows）
  static Future<bool> simulateCopy() async {
    if (!Platform.isWindows) return false;
    return _simulateModifierKeyWithRetry(PhysicalKeyboardKey.keyC, ModifierKey.controlModifier);
  }
  
  /// 模拟 Ctrl+V 粘贴操作（仅 Windows）
  static Future<bool> simulatePaste() async {
    if (!Platform.isWindows) return false;
    // 粘贴前稍等，确保剪贴板数据已写入
    await Future.delayed(const Duration(milliseconds: 50));
    return _simulateModifierKeyWithRetry(PhysicalKeyboardKey.keyV, ModifierKey.controlModifier);
  }
  
  /// 模拟 Ctrl+X 剪切操作（仅 Windows）
  static Future<bool> simulateCut() async {
    if (!Platform.isWindows) return false;
    return _simulateModifierKeyWithRetry(PhysicalKeyboardKey.keyX, ModifierKey.controlModifier);
  }
  
  /// 模拟 Ctrl+Z 撤销操作（仅 Windows）
  static Future<bool> simulateUndo() async {
    if (!Platform.isWindows) return false;
    return _simulateModifierKeyWithRetry(PhysicalKeyboardKey.keyZ, ModifierKey.controlModifier);
  }
  
  /// 模拟 Ctrl+Y 重做操作（仅 Windows）
  static Future<bool> simulateRedo() async {
    if (!Platform.isWindows) return false;
    return _simulateModifierKeyWithRetry(PhysicalKeyboardKey.keyY, ModifierKey.controlModifier);
  }
}
