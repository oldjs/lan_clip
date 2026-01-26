import 'dart:convert';
import 'dart:typed_data';

/// 剪贴板数据类型
enum ClipboardDataType {
  text,
  image,
}

/// 剪贴板数据模型，用于跨设备传输
class ClipboardContent {
  final ClipboardDataType type;
  final String? text;
  final Uint8List? imageData;
  final DateTime timestamp;

  ClipboardContent({
    required this.type,
    this.text,
    this.imageData,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// 创建文本内容
  factory ClipboardContent.text(String text) {
    return ClipboardContent(
      type: ClipboardDataType.text,
      text: text,
    );
  }

  /// 创建图片内容
  factory ClipboardContent.image(Uint8List data) {
    return ClipboardContent(
      type: ClipboardDataType.image,
      imageData: data,
    );
  }

  /// 序列化为传输格式
  /// 格式: TYPE:TEXT\n内容 或 TYPE:IMAGE\n<base64>
  String serialize() {
    switch (type) {
      case ClipboardDataType.text:
        return 'TYPE:TEXT\n${text ?? ''}';
      case ClipboardDataType.image:
        final base64Data = base64Encode(imageData ?? Uint8List(0));
        return 'TYPE:IMAGE\n$base64Data';
    }
  }

  /// 从传输格式反序列化
  static ClipboardContent? deserialize(String data) {
    final newlineIndex = data.indexOf('\n');
    if (newlineIndex == -1) return null;

    final typeLine = data.substring(0, newlineIndex);
    final content = data.substring(newlineIndex + 1);

    if (typeLine == 'TYPE:TEXT') {
      return ClipboardContent.text(content);
    } else if (typeLine == 'TYPE:IMAGE') {
      try {
        final imageData = base64Decode(content);
        return ClipboardContent.image(imageData);
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  /// 判断是否为剪贴板同步消息
  static bool isSyncMessage(String data) {
    return data.startsWith('TYPE:TEXT\n') || data.startsWith('TYPE:IMAGE\n');
  }
}
