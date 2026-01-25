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
        await simulateBackspace();
        return '退格';
      case cmdSpace:
        await simulateSpace();
        return '空格';
      case cmdClear:
        await simulateClear();
        return '清空';
      case cmdEnter:
        await simulateEnter();
        return '回车';
      case cmdArrowUp:
        await simulateArrow(PhysicalKeyboardKey.arrowUp);
        return '上移';
      case cmdArrowDown:
        await simulateArrow(PhysicalKeyboardKey.arrowDown);
        return '下移';
      case cmdArrowLeft:
        await simulateArrow(PhysicalKeyboardKey.arrowLeft);
        return '左移';
      case cmdArrowRight:
        await simulateArrow(PhysicalKeyboardKey.arrowRight);
        return '右移';
      // 鼠标控制指令
      case cmdMouseLeftClick:
        MouseService().leftClick();
        return null; // 鼠标操作不显示提示
      case cmdMouseRightClick:
        MouseService().rightClick();
        return null;
      case cmdMouseLeftDown:
        MouseService().leftDown();
        return null;
      case cmdMouseLeftUp:
        MouseService().leftUp();
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
  
  /// 模拟退格键
  static Future<bool> simulateBackspace() async {
    if (!Platform.isWindows) return false;
    try {
      await keyPressSimulator.simulateKeyDown(PhysicalKeyboardKey.backspace, []);
      await keyPressSimulator.simulateKeyUp(PhysicalKeyboardKey.backspace, []);
      return true;
    } catch (e) {
      return false;
    }
  }
  
  /// 模拟空格键
  static Future<bool> simulateSpace() async {
    if (!Platform.isWindows) return false;
    try {
      await keyPressSimulator.simulateKeyDown(PhysicalKeyboardKey.space, []);
      await keyPressSimulator.simulateKeyUp(PhysicalKeyboardKey.space, []);
      return true;
    } catch (e) {
      return false;
    }
  }
  
  /// 模拟 Ctrl+A 全选后 Delete 清空
  static Future<bool> simulateClear() async {
    if (!Platform.isWindows) return false;
    try {
      // Ctrl+A 全选
      await keyPressSimulator.simulateKeyDown(
        PhysicalKeyboardKey.keyA,
        [ModifierKey.controlModifier],
      );
      await keyPressSimulator.simulateKeyUp(
        PhysicalKeyboardKey.keyA,
        [ModifierKey.controlModifier],
      );
      // 短暂延迟
      await Future.delayed(const Duration(milliseconds: 30));
      // Delete 删除
      await keyPressSimulator.simulateKeyDown(PhysicalKeyboardKey.delete, []);
      await keyPressSimulator.simulateKeyUp(PhysicalKeyboardKey.delete, []);
      return true;
    } catch (e) {
      return false;
    }
  }
  
  /// 模拟回车键
  static Future<bool> simulateEnter() async {
    if (!Platform.isWindows) return false;
    try {
      await keyPressSimulator.simulateKeyDown(PhysicalKeyboardKey.enter, []);
      await keyPressSimulator.simulateKeyUp(PhysicalKeyboardKey.enter, []);
      return true;
    } catch (e) {
      return false;
    }
  }
  
  /// 模拟方向键
  static Future<bool> simulateArrow(PhysicalKeyboardKey key) async {
    if (!Platform.isWindows) return false;
    try {
      await keyPressSimulator.simulateKeyDown(key, []);
      await keyPressSimulator.simulateKeyUp(key, []);
      return true;
    } catch (e) {
      return false;
    }
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

  /// 模拟 Ctrl+V 粘贴操作（仅 Windows）
  static Future<bool> simulatePaste() async {
    if (!Platform.isWindows) return false;
    
    try {
      // 短暂延迟确保剪切板已写入
      await Future.delayed(const Duration(milliseconds: 50));
      
      // 模拟按下 Ctrl+V
      await keyPressSimulator.simulateKeyDown(
        PhysicalKeyboardKey.keyV,
        [ModifierKey.controlModifier],
      );
      
      // 模拟释放 Ctrl+V
      await keyPressSimulator.simulateKeyUp(
        PhysicalKeyboardKey.keyV,
        [ModifierKey.controlModifier],
      );
      
      return true;
    } catch (e) {
      return false;
    }
  }
}
