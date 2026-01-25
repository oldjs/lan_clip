import 'package:flutter/services.dart';

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
}
