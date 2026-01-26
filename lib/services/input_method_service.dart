import 'dart:io';
import 'package:flutter/services.dart';

/// 输入法服务 - 封装平台相关的输入法操作
class InputMethodService {
  // 与 Android 原生通信的 Channel
  static const _channel = MethodChannel('com.example.lan_clip/input_method');

  /// 显示系统输入法选择器（仅 Android 支持）
  static Future<bool> showInputMethodPicker() async {
    if (!Platform.isAndroid) {
      return false;
    }
    
    try {
      final result = await _channel.invokeMethod('showInputMethodPicker');
      return result == true;
    } on PlatformException {
      return false;
    }
  }
  
  /// 检查是否支持输入法切换（仅 Android）
  static bool get isSupported => Platform.isAndroid;
}
