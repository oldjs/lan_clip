import 'dart:async';
import 'dart:io';
import 'dart:convert';
import '../models/device.dart';
import '../models/clipboard_data.dart';

/// 认证消息结果
class AuthResult {
  final bool success;
  final String? message;
  final String? error;

  AuthResult({required this.success, this.message, this.error});
}

/// 发送结果
class SendResult {
  final bool success;
  final String? error;

  SendResult({required this.success, this.error});
}

/// TCP 通信服务
class SocketService {
  static const int defaultPort = 8888;
  
  ServerSocket? _server;
  final _messageController = StreamController<AuthResult>.broadcast();
  
  // 密码验证回调
  Future<bool> Function(String hash)? _verifyPassword;
  bool _requiresPassword = false;
  
  /// 设置密码验证
  void setPasswordVerification({
    required bool requiresPassword,
    Future<bool> Function(String hash)? verifyPassword,
  }) {
    _requiresPassword = requiresPassword;
    _verifyPassword = verifyPassword;
  }
  
  /// 接收到的消息流
  Stream<AuthResult> get messageStream => _messageController.stream;
  
  /// 启动 TCP 服务器（Windows 端）
  Future<int> startServer({int port = defaultPort}) async {
    await _server?.close();
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    
    _server!.listen((Socket client) {
      _handleClient(client);
    });
    
    return _server!.port;
  }
  
  /// 处理客户端连接
  void _handleClient(Socket client) {
    final buffer = StringBuffer();
    
    client.listen(
      (data) {
        buffer.write(utf8.decode(data));
      },
      onDone: () async {
        final rawMessage = buffer.toString();
        if (rawMessage.isEmpty) {
          client.close();
          return;
        }
        
        // 解析认证消息格式: AUTH:哈希\n内容
        final result = await _parseAndVerifyMessage(rawMessage);
        _messageController.add(result);
        client.close();
      },
      onError: (error) {
        client.close();
      },
    );
  }
  
  /// 解析并验证消息
  Future<AuthResult> _parseAndVerifyMessage(String rawMessage) async {
    // 查找第一个换行符分隔认证头和内容
    final newlineIndex = rawMessage.indexOf('\n');
    if (newlineIndex == -1) {
      // 旧格式兼容：无认证头，直接是内容
      if (!_requiresPassword) {
        return AuthResult(success: true, message: rawMessage);
      }
      return AuthResult(success: false, error: '需要密码验证');
    }
    
    final authLine = rawMessage.substring(0, newlineIndex);
    final content = rawMessage.substring(newlineIndex + 1);
    
    // 解析认证头: AUTH:哈希
    if (!authLine.startsWith('AUTH:')) {
      // 旧格式兼容
      if (!_requiresPassword) {
        return AuthResult(success: true, message: rawMessage);
      }
      return AuthResult(success: false, error: '需要密码验证');
    }
    
    final hash = authLine.substring(5); // 去掉 "AUTH:"
    
    // 不需要密码时，任何认证都通过
    if (!_requiresPassword) {
      return AuthResult(success: true, message: content);
    }
    
    // 需要密码时验证哈希
    if (hash.isEmpty) {
      return AuthResult(success: false, error: '需要密码验证');
    }
    
    if (_verifyPassword != null) {
      final valid = await _verifyPassword!(hash);
      if (valid) {
        return AuthResult(success: true, message: content);
      }
      return AuthResult(success: false, error: '密码错误');
    }
    
    return AuthResult(success: false, error: '验证配置错误');
  }

  /// 发送消息到服务器（Android 端）
  /// passwordHash 为空表示不带密码
  Future<SendResult> sendMessage(String ip, int port, String message, {String? passwordHash}) async {
    try {
      final socket = await Socket.connect(ip, port, 
        timeout: const Duration(seconds: 5),
      );
      
      // 构建认证消息格式: AUTH:哈希\n内容
      final authMessage = 'AUTH:${passwordHash ?? ''}\n$message';
      socket.write(authMessage);
      await socket.flush();
      await socket.close();
      return SendResult(success: true);
    } catch (e) {
      return SendResult(success: false, error: e.toString());
    }
  }
  
  /// 推送剪贴板内容到多个设备(电脑端使用)
  /// 向所有已连接的手机推送剪贴板内容
  Future<void> pushClipboardToDevices(
    List<Device> devices, 
    ClipboardContent content,
  ) async {
    if (devices.isEmpty) return;
    
    final data = content.serialize();
    
    // 并行推送到所有设备
    await Future.wait(
      devices.where((d) => d.syncPort != null).map((device) async {
        try {
          final socket = await Socket.connect(
            device.ip, 
            device.syncPort!,
            timeout: const Duration(seconds: 3),
          );
          socket.write(data);
          await socket.flush();
          await socket.close();
        } catch (e) {
          // 忽略单个设备的推送失败
        }
      }),
    );
  }

  /// 停止服务器
  void dispose() {
    _server?.close();
    _messageController.close();
  }
}
