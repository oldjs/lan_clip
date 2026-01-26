import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:clipboard_watcher/clipboard_watcher.dart';
import 'package:pasteboard/pasteboard.dart';
import '../models/clipboard_data.dart';

/// 剪贴板监听服务(Windows端)
/// 监听系统剪贴板变化，读取文本和图片内容
class ClipboardWatcherService with ClipboardListener {
  final _contentController = StreamController<ClipboardContent>.broadcast();
  bool _isWatching = false;
  String? _lastTextHash;      // 上次文本哈希，防止重复
  int? _lastImageLength;      // 上次图片大小，防止重复
  bool _ignoreNext = false;   // 忽略下一次变化(自己写入时)
  
  /// 剪贴板内容变化流
  Stream<ClipboardContent> get contentStream => _contentController.stream;
  
  /// 是否正在监听
  bool get isWatching => _isWatching;
  
  /// 开始监听剪贴板
  Future<void> startWatching() async {
    if (!Platform.isWindows) return;
    if (_isWatching) return;
    
    clipboardWatcher.addListener(this);
    await clipboardWatcher.start();
    _isWatching = true;
  }
  
  /// 停止监听剪贴板
  Future<void> stopWatching() async {
    if (!_isWatching) return;
    
    clipboardWatcher.removeListener(this);
    await clipboardWatcher.stop();
    _isWatching = false;
  }
  
  /// 设置忽略下一次剪贴板变化
  void ignoreNextChange() {
    _ignoreNext = true;
  }
  
  /// 剪贴板变化回调
  @override
  Future<void> onClipboardChanged() async {
    // 忽略自己触发的变化
    if (_ignoreNext) {
      _ignoreNext = false;
      return;
    }
    
    // 优先检查图片
    final imageData = await _readImage();
    if (imageData != null && imageData.isNotEmpty) {
      // 检查是否重复
      if (_lastImageLength != imageData.length) {
        _lastImageLength = imageData.length;
        _lastTextHash = null;
        final content = ClipboardContent.image(imageData);
        _contentController.add(content);
      }
      return;
    }
    
    // 检查文本
    final textData = await Clipboard.getData(Clipboard.kTextPlain);
    if (textData?.text != null && textData!.text!.isNotEmpty) {
      final text = textData.text!;
      final hash = text.hashCode.toString();
      // 检查是否重复
      if (_lastTextHash != hash) {
        _lastTextHash = hash;
        _lastImageLength = null;
        final content = ClipboardContent.text(text);
        _contentController.add(content);
      }
    }
  }
  
  /// 读取剪贴板图片
  Future<Uint8List?> _readImage() async {
    try {
      final imageBytes = await Pasteboard.image;
      return imageBytes;
    } catch (e) {
      return null;
    }
  }
  
  /// 释放资源
  void dispose() {
    stopWatching();
    _contentController.close();
  }
}
