import 'dart:async';
import 'dart:io';
import 'dart:convert';
import '../models/clipboard_data.dart';
import '../services/clipboard_service.dart';
import '../services/encryption_service.dart';
import '../services/phone_control_service.dart';
import 'package:cryptography/cryptography.dart';

/// 手机端剪贴板同步接收服务
/// 监听电脑端推送的剪贴板内容
class ClipboardSyncService {
  static const int defaultSyncPort = 8889;
  
  ServerSocket? _server;
  final _contentController = StreamController<ClipboardContent>.broadcast();
  int _port = defaultSyncPort;
  
  SecretKey? _encryptionKey;
  bool _encryptionEnabled = false;

  void setEncryption({required bool enabled, SecretKey? key}) {
    _encryptionEnabled = enabled;
    _encryptionKey = key;
  }
  
  /// 接收到的剪贴板内容流
  Stream<ClipboardContent> get contentStream => _contentController.stream;
  
  /// 当前监听端口
  int get port => _port;
  
  /// 启动同步服务(手机端)
  Future<int> startServer({int port = defaultSyncPort}) async {
    await _server?.close();
    
    // 尝试绑定端口，如果失败则使用随机端口
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    } catch (e) {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    }
    
    _port = _server!.port;
    
    _server!.listen((Socket client) {
      _handleClient(client);
    });
    
    return _port;
  }
  
  /// 处理来自电脑端的连接
  void _handleClient(Socket client) {
    final buffer = <int>[];
    
    client.listen(
      (data) {
        buffer.addAll(data);
      },
      onDone: () async {
        if (buffer.isEmpty) {
          client.close();
          return;
        }
        
        try {
          var message = utf8.decode(buffer);
          
          // 如果消息加密，尝试解密
          if (EncryptionService.isEncrypted(message)) {
            if (_encryptionEnabled && _encryptionKey != null) {
              final decrypted = await EncryptionService.decrypt(message, _encryptionKey!);
              if (decrypted != null) {
                message = decrypted;
              } else {
                // 解密失败，忽略
                client.close();
                return;
              }
            } else {
              // 未启用加密或没有密钥，但收到加密消息，忽略
              client.close();
              return;
            }
          }

          if (ClipboardService.isCommand(message)) {
            await PhoneControlService.handleCommand(message);
            client.close();
            return;
          }

          final content = ClipboardContent.deserialize(message);
          if (content != null) {
            _contentController.add(content);
          }
        } catch (e) {
          // 解析失败，忽略
        }
        
        client.close();
      },
      onError: (error) {
        client.close();
      },
    );
  }
  
  /// 停止服务
  Future<void> stopServer() async {
    await _server?.close();
    _server = null;
  }
  
  /// 释放资源
  void dispose() {
    stopServer();
    _contentController.close();
  }
}
