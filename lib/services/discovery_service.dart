import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:network_info_plus/network_info_plus.dart';
import '../models/device.dart';

/// UDP 设备发现服务
class DiscoveryService {
  static const int discoveryPort = 9999;
  static const String discoveryMessage = 'LAN_CLIP_DISCOVER';
  
  RawDatagramSocket? _socket;
  final _deviceController = StreamController<Device>.broadcast();
  String _deviceName = 'Unknown';
  int _tcpPort = 8888;
  
  /// 发现的设备流
  Stream<Device> get deviceStream => _deviceController.stream;
  
  /// 获取本机 IP 地址
  Future<String?> getLocalIp() async {
    try {
      final info = NetworkInfo();
      return await info.getWifiIP();
    } catch (e) {
      // 备用方案：遍历网络接口
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    }
    return null;
  }

  /// 启动 UDP 监听（服务端模式 - Windows）
  Future<void> startListening(String deviceName, int tcpPort) async {
    _deviceName = deviceName;
    _tcpPort = tcpPort;
    
    _socket?.close();
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, discoveryPort);
    
    _socket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = _socket!.receive();
        if (datagram != null) {
          final message = utf8.decode(datagram.data);
          if (message == discoveryMessage) {
            // 回复发现请求
            final response = 'LAN_CLIP|$_deviceName|$_tcpPort';
            _socket!.send(
              utf8.encode(response),
              datagram.address,
              datagram.port,
            );
          }
        }
      }
    });
  }

  /// 发送发现广播（客户端模式 - Android）
  Future<void> sendDiscoveryBroadcast() async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    
    // 发送广播
    socket.send(
      utf8.encode(discoveryMessage),
      InternetAddress('255.255.255.255'),
      discoveryPort,
    );
    
    // 监听响应
    socket.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = socket.receive();
        if (datagram != null) {
          final response = utf8.decode(datagram.data);
          if (response.startsWith('LAN_CLIP|')) {
            final device = Device.fromDiscoveryResponse(
              response,
              datagram.address.address,
            );
            _deviceController.add(device);
          }
        }
      }
    });
    
    // 5秒后关闭
    Future.delayed(const Duration(seconds: 5), () {
      socket.close();
    });
  }

  /// 停止服务
  void dispose() {
    _socket?.close();
    _deviceController.close();
  }
}
