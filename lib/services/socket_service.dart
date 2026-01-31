import 'dart:async';
import 'dart:io';
import 'dart:convert';
import '../models/device.dart';
import '../models/clipboard_data.dart';
import '../models/remote_request.dart';
import '../services/encryption_service.dart';
import 'remote_request_codec.dart';
import 'package:cryptography/cryptography.dart';

/// 认证消息结果
class AuthResult {
  final bool success;
  final String? message;
  final String? error;
  final bool wasEncrypted;

  AuthResult({required this.success, this.message, this.error, this.wasEncrypted = false});
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
  Future<RemoteResponse?> Function(RemoteRequest request)? _requestHandler;
  
  // 加密密钥（由外部设置）
  SecretKey? _encryptionKey;
  bool _encryptionEnabled = false;

  /// 设置加密
  void setEncryption({
    required bool enabled,
    SecretKey? key,
  }) {
    if (enabled && key == null) {
      _encryptionEnabled = false;
      _encryptionKey = null;
      return;
    }
    _encryptionEnabled = enabled;
    _encryptionKey = key;
  }
  
  /// 设置密码验证
  void setPasswordVerification({
    required bool requiresPassword,
    Future<bool> Function(String hash)? verifyPassword,
  }) {
    _requiresPassword = requiresPassword;
    _verifyPassword = verifyPassword;
  }

  /// 设置请求处理器（用于请求-响应）
  void setRequestHandler({
    Future<RemoteResponse?> Function(RemoteRequest request)? handler,
  }) {
    _requestHandler = handler;
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
        if (result.success && result.message != null) {
          // 请求-响应消息直接处理并返回
          final request = RemoteRequestCodec.tryDecodeRequest(result.message!);
          if (request != null) {
            final response = await _handleRequest(request);
            if (response != null) {
              var payload = RemoteRequestCodec.encodeResponse(response);
              // 只有当请求是加密的才加密响应（通过 result.wasEncrypted 判断）
              if (result.wasEncrypted && _encryptionEnabled && _encryptionKey != null) {
                payload = await EncryptionService.encrypt(payload, _encryptionKey!);
              }
              client.write(payload);
              await client.flush();
            }
            client.close();
            return;
          }
        }
        _messageController.add(result);
        client.close();
      },
      onError: (error) {
        client.close();
      },
    );
  }

  Future<RemoteResponse?> _handleRequest(RemoteRequest request) async {
    if (_requestHandler == null) {
      return RemoteResponse.fail(request.id, '请求不支持');
    }
    try {
      return await _requestHandler!(request);
    } catch (_) {
      return RemoteResponse.fail(request.id, '请求处理失败');
    }
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
    var content = rawMessage.substring(newlineIndex + 1);
    
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
      // 检查内容是否加密
      bool wasEncrypted = EncryptionService.isEncrypted(content);
      if (wasEncrypted) {
        if (_encryptionKey != null) {
          final decrypted = await EncryptionService.decrypt(content, _encryptionKey!);
          if (decrypted != null) {
            content = decrypted;
          } else {
            return AuthResult(success: false, error: '解密失败');
          }
        }
      }
      return AuthResult(success: true, message: content, wasEncrypted: wasEncrypted);
    }
    
    // 需要密码时验证哈希
    if (hash.isEmpty) {
      return AuthResult(success: false, error: '需要密码验证');
    }
    
    if (_verifyPassword != null) {
      final valid = await _verifyPassword!(hash);
      if (valid) {
        // 检查内容是否加密
        bool wasEncrypted = EncryptionService.isEncrypted(content);
        if (wasEncrypted) {
          if (_encryptionKey != null) {
            final decrypted = await EncryptionService.decrypt(content, _encryptionKey!);
            if (decrypted != null) {
              content = decrypted;
            } else {
              return AuthResult(success: false, error: '解密失败');
            }
          }
        }
        return AuthResult(success: true, message: content, wasEncrypted: wasEncrypted);
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
      
      var finalMessage = message;
      if (_encryptionEnabled && _encryptionKey != null) {
        finalMessage = await EncryptionService.encrypt(message, _encryptionKey!);
      }

      // 构建认证消息格式: AUTH:哈希\n内容
      final authMessage = 'AUTH:${passwordHash ?? ''}\n$finalMessage';
      socket.write(authMessage);
      await socket.flush();
      await socket.close();
      return SendResult(success: true);
    } catch (e) {
      return SendResult(success: false, error: e.toString());
    }
  }

  /// 发送请求并等待响应
  Future<RemoteResponse?> sendRequest(
    String ip,
    int port,
    RemoteRequest request, {
    String? passwordHash,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      final socket = await Socket.connect(ip, port, timeout: timeout);

      var payload = RemoteRequestCodec.encodeRequest(request);
      if (_encryptionEnabled && _encryptionKey != null) {
        payload = await EncryptionService.encrypt(payload, _encryptionKey!);
      }

      final authMessage = 'AUTH:${passwordHash ?? ''}\n$payload';
      socket.write(authMessage);
      await socket.flush();
      
      // 关闭写入端，触发服务端的 onDone 开始处理请求
      // close() 只关闭写入方向，仍可接收响应数据
      socket.close();

      final responseCompleter = Completer<String>();
      final responseBuffer = StringBuffer();

      socket.listen(
        (data) => responseBuffer.write(utf8.decode(data)),
        onDone: () => responseCompleter.complete(responseBuffer.toString()),
        onError: (_) => responseCompleter.complete(responseBuffer.toString()),
      );

      var responseText = await responseCompleter.future.timeout(timeout);
      if (responseText.isEmpty) {
        await socket.close();
        return null;
      }

      if (EncryptionService.isEncrypted(responseText) && _encryptionKey != null) {
        final decrypted = await EncryptionService.decrypt(responseText, _encryptionKey!);
        if (decrypted == null) {
          await socket.close();
          return null;
        }
        responseText = decrypted;
      }
      final response = RemoteRequestCodec.tryDecodeResponse(responseText);
      await socket.close();
      return response;
    } catch (e) {
      print('[SocketService] sendRequest error: $e');
      return null;
    }
  }
  
  /// 推送剪贴板内容到多个设备(电脑端使用)
  /// 向所有已连接的手机推送剪贴板内容
  Future<void> pushClipboardToDevices(
    List<Device> devices, 
    ClipboardContent content,
  ) async {
    if (devices.isEmpty) return;
    
    var data = content.serialize();
    if (_encryptionEnabled && _encryptionKey != null) {
      data = await EncryptionService.encrypt(data, _encryptionKey!);
    }
    
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

  /// 推送控制指令到多个设备(电脑端使用)
  Future<void> pushCommandToDevices(
    List<Device> devices,
    String command,
  ) async {
    if (devices.isEmpty) return;

    var data = command;
    if (_encryptionEnabled && _encryptionKey != null) {
      data = await EncryptionService.encrypt(data, _encryptionKey!);
    }

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
        } catch (_) {
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

  /// 连接到设备并测试连接
  /// 用于扫码闪电传功能
  Future<bool> connectToDevice(Device device, {String? passwordHash}) async {
    try {
      // 发送测试请求
      final result = await sendMessage(
        device.ip,
        device.port,
        'PING',
        passwordHash: passwordHash,
      );
      return result.success;
    } catch (e) {
      return false;
    }
  }
}
