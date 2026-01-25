import 'dart:io';
import 'package:flutter/services.dart';
import 'package:keypress_simulator/keypress_simulator.dart';

/// 剪切板服务
class ClipboardService {
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
