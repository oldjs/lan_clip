import 'dart:convert';

/// 二维码会话数据模型
/// 用于扫码闪电传功能
class QRSession {
  /// 发送方 IP 地址
  final String ip;
  
  /// 监听端口
  final int port;
  
  /// 设备名称
  final String name;
  
  /// 一次性验证令牌
  final String token;
  
  /// 过期时间戳（毫秒）
  final int timestamp;
  
  /// 会话有效期（默认 5 分钟）
  static const int validityDuration = 5 * 60 * 1000;
  
  QRSession({
    required this.ip,
    required this.port,
    required this.name,
    required this.token,
    required this.timestamp,
  });
  
  /// 从 JSON 构造
  factory QRSession.fromJson(Map<String, dynamic> json) {
    return QRSession(
      ip: json['ip'] as String,
      port: json['port'] as int,
      name: json['name'] as String,
      token: json['token'] as String,
      timestamp: json['ts'] as int,
    );
  }
  
  /// 转为 JSON
  Map<String, dynamic> toJson() {
    return {
      'ip': ip,
      'port': port,
      'name': name,
      'token': token,
      'ts': timestamp,
    };
  }
  
  /// 生成二维码 URL
  String toQrUrl() {
    final jsonStr = jsonEncode(toJson());
    final base64Str = base64UrlEncode(utf8.encode(jsonStr));
    return 'lanclip://$base64Str';
  }
  
  /// 从二维码 URL 解析
  static QRSession? fromQrUrl(String url) {
    try {
      if (!url.startsWith('lanclip://')) {
        return null;
      }
      
      final base64Str = url.substring('lanclip://'.length);
      final jsonBytes = base64.decode(base64.normalize(base64Str));
      final jsonStr = utf8.decode(jsonBytes);
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      
      return QRSession.fromJson(json);
    } catch (e) {
      return null;
    }
  }
  
  /// 检查是否过期
  bool get isExpired {
    final now = DateTime.now().millisecondsSinceEpoch;
    return now - timestamp > validityDuration;
  }
  
  /// 剩余有效时间（秒）
  int get remainingSeconds {
    final now = DateTime.now().millisecondsSinceEpoch;
    final remaining = validityDuration - (now - timestamp);
    return remaining ~/ 1000;
  }
  
  @override
  String toString() {
    return 'QRSession(ip: $ip, port: $port, name: $name, expired: $isExpired)';
  }
}
