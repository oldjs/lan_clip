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
  final _connectedDeviceController = StreamController<Device>.broadcast(); // 电脑端记录连接的手机
  String _deviceName = 'Unknown';
  int _tcpPort = 8888;
  int? _syncPort;               // 剪贴板同步端口(手机端)
  bool _requiresPassword = false;  // 是否需要密码验证
  
  /// 发现的设备流
  Stream<Device> get deviceStream => _deviceController.stream;
  
  /// 连接的设备流(电脑端使用，记录发现请求的手机)
  Stream<Device> get connectedDeviceStream => _connectedDeviceController.stream;
  
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

  /// 设置是否需要密码
  void setRequiresPassword(bool value) {
    _requiresPassword = value;
  }
  
  /// 设置剪贴板同步端口(手机端)
  void setSyncPort(int? port) {
    _syncPort = port;
  }

  /// 启动 UDP 监听（服务端模式 - Windows）
  Future<void> startListening(String deviceName, int tcpPort, {bool requiresPassword = false}) async {
    _deviceName = deviceName;
    _tcpPort = tcpPort;
    _requiresPassword = requiresPassword;
    
    _socket?.close();
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, discoveryPort);
    
    _socket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = _socket!.receive();
        if (datagram != null) {
          final message = utf8.decode(datagram.data);
          // 解析发现请求，可能携带同步端口: LAN_CLIP_DISCOVER|syncPort
          if (message.startsWith(discoveryMessage)) {
            // 解析手机端同步端口
            int? mobileSyncPort;
            final parts = message.split('|');
            if (parts.length >= 2) {
              mobileSyncPort = int.tryParse(parts[1]);
            }
            
            // 记录连接的手机设备
            if (mobileSyncPort != null) {
              final mobileDevice = Device(
                ip: datagram.address.address,
                port: mobileSyncPort,
                name: 'Mobile',
                syncPort: mobileSyncPort,
              );
              _connectedDeviceController.add(mobileDevice);
            }
            
            // 回复发现请求，包含密码标志
            final passwordFlag = _requiresPassword ? '1' : '0';
            final response = 'LAN_CLIP|$_deviceName|$_tcpPort|$passwordFlag';
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
  /// syncPort: 手机端剪贴板同步监听端口
  Future<void> sendDiscoveryBroadcast({int? syncPort}) async {
    _syncPort = syncPort;
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    
    // 发送广播，携带同步端口信息
    final message = syncPort != null 
        ? '$discoveryMessage|$syncPort' 
        : discoveryMessage;
    socket.send(
      utf8.encode(message),
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
    _connectedDeviceController.close();
  }
}
