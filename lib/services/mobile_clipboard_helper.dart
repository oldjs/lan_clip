import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import '../models/clipboard_data.dart';

/// 移动端剪贴板工具类
/// 支持文本和图片写入剪贴板
class MobileClipboardHelper {
  /// 将剪贴板内容写入系统剪贴板
  static Future<bool> writeContent(ClipboardContent content) async {
    try {
      switch (content.type) {
        case ClipboardDataType.text:
          if (content.text != null) {
            await Clipboard.setData(ClipboardData(text: content.text!));
            return true;
          }
          return false;
          
        case ClipboardDataType.image:
          if (content.imageData != null) {
            return await _writeImage(content.imageData!);
          }
          return false;
      }
    } catch (e) {
      return false;
    }
  }
  
  /// 写入图片到剪贴板
  /// Android 原生剪贴板不支持直接写入图片
  /// 这里保存为临时文件，通过 Intent 分享或提示用户
  static Future<bool> _writeImage(Uint8List imageData) async {
    try {
      // Android 系统剪贴板不直接支持图片
      // 我们将图片保存到临时目录，让用户手动分享
      // 或者通过平台通道实现原生图片剪贴板写入
      
      // 暂时保存到临时文件
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/clipboard_image_${DateTime.now().millisecondsSinceEpoch}.png');
      await tempFile.writeAsBytes(imageData);
      
      // 返回true表示图片已保存，UI层可以提示用户
      return true;
    } catch (e) {
      return false;
    }
  }
  
  /// 获取最近保存的图片路径
  static Future<String?> getLastSavedImagePath() async {
    try {
      final tempDir = Directory.systemTemp;
      final files = tempDir.listSync()
          .whereType<File>()
          .where((f) => f.path.contains('clipboard_image_'))
          .toList();
      
      if (files.isEmpty) return null;
      
      // 按修改时间排序，返回最新的
      files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      return files.first.path;
    } catch (e) {
      return null;
    }
  }
  
  /// 清理临时图片文件
  static Future<void> cleanupTempImages() async {
    try {
      final tempDir = Directory.systemTemp;
      final files = tempDir.listSync()
          .whereType<File>()
          .where((f) => f.path.contains('clipboard_image_'));
      
      for (final file in files) {
        await file.delete();
      }
    } catch (e) {
      // 忽略清理错误
    }
  }
}
