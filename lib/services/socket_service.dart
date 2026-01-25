import 'dart:async';
import 'dart:io';
import 'dart:convert';

/// TCP 通信服务
class SocketService {
  static const int defaultPort = 8888;
  
  ServerSocket? _server;
  final _messageController = StreamController<String>.broadcast();
  
  /// 接收到的消息流
  Stream<String> get messageStream => _messageController.stream;
  
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
      onDone: () {
        final message = buffer.toString();
        if (message.isNotEmpty) {
          _messageController.add(message);
        }
        client.close();
      },
      onError: (error) {
        client.close();
      },
    );
  }

  /// 发送消息到服务器（Android 端）
  Future<bool> sendMessage(String ip, int port, String message) async {
    try {
      final socket = await Socket.connect(ip, port, 
        timeout: const Duration(seconds: 5),
      );
      socket.write(message);
      await socket.flush();
      await socket.close();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 停止服务器
  void dispose() {
    _server?.close();
    _messageController.close();
  }
}
