import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import '../models/device.dart';
import '../models/qr_session.dart';

/// 扫码闪电传服务
/// 管理二维码生成、验证和快速连接
class QuickTransferService {
  // 单例模式
  static final QuickTransferService _instance = QuickTransferService._internal();
  factory QuickTransferService() => _instance;
  QuickTransferService._internal();
  
  // 当前活跃的会话
  QRSession? _currentSession;
  Timer? _timeoutTimer;
  // ignore: unused_field - 保留用于未来扩展客户端连接回调
  Function(Socket socket)? _onClientConnected;
  
  /// 当前会话
  QRSession? get currentSession => _currentSession;
  
  /// 生成随机令牌
  String _generateToken() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(32, (_) => chars[random.nextInt(chars.length)]).join();
  }
  
  /// 获取本机 IP 地址
  Future<String?> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          // 跳过 loopback 和虚拟网卡，优先选择常见网卡
          if (!addr.isLoopback && 
              !addr.address.startsWith('169.254') &&
              !addr.address.startsWith('127.') &&
              RegExp(r'wifi|ethernet|以太网|wlan', caseSensitive: false).hasMatch(interface.name)) {
            return addr.address;
          }
        }
      }
      
      // 如果找不到合适的，返回第一个非 loopback
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback) {
            return addr.address;
          }
        }
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }
  
  /// 开始二维码会话
  /// 
  /// [port] - 监听端口（复用主服务端口）
  /// [deviceName] - 设备名称
  /// [onClientConnected] - 客户端连接成功回调
  /// 
  /// 返回二维码 URL，失败返回 null
  Future<String?> startSession({
    required int port,
    required String deviceName,
    Function(Socket socket)? onClientConnected,
  }) async {
    // 先关闭之前的会话
    await stopSession();
    
    try {
      // 获取本机 IP
      final ip = await _getLocalIp();
      if (ip == null) {
        debugPrint('QuickTransfer: 无法获取本机 IP');
        return null;
      }
      
      // 生成会话
      final token = _generateToken();
      _currentSession = QRSession(
        ip: ip,
        port: port,
        name: deviceName,
        token: token,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      
      _onClientConnected = onClientConnected;
      
      // 启动临时监听（复用主服务端口，由主服务处理连接）
      // 这里不需要单独启动 ServerSocket，因为主服务已经在监听
      // 我们只需要设置验证回调即可
      
      // 启动超时定时器
      _timeoutTimer = Timer(Duration(milliseconds: QRSession.validityDuration), () {
        debugPrint('QuickTransfer: 会话已过期');
        stopSession();
      });
      
      debugPrint('QuickTransfer: 会话已创建 - ${_currentSession!.toQrUrl()}');
      return _currentSession!.toQrUrl();
      
    } catch (e) {
      debugPrint('QuickTransfer: 创建会话失败 - $e');
      return null;
    }
  }
  
  /// 停止会话
  Future<void> stopSession() async {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _currentSession = null;
    _onClientConnected = null;
    debugPrint('QuickTransfer: 会话已停止');
  }
  
  /// 验证令牌
  /// 
  /// 由 SocketService 在处理新连接时调用
  bool verifyToken(String token) {
    if (_currentSession == null) {
      debugPrint('QuickTransfer: 验证失败 - 无活跃会话');
      return false;
    }
    
    if (_currentSession!.isExpired) {
      debugPrint('QuickTransfer: 验证失败 - 会话已过期');
      stopSession();
      return false;
    }
    
    final isValid = _currentSession!.token == token;
    debugPrint('QuickTransfer: 令牌验证${isValid ? "成功" : "失败"}');
    
    if (isValid) {
      // 验证成功后停止会话（一次性使用）
      _timeoutTimer?.cancel();
    }
    
    return isValid;
  }
  
  /// 从二维码 URL 创建设备对象
  /// 
  /// 在 Android 端扫码成功后调用
  static Device? createDeviceFromUrl(String url) {
    final session = QRSession.fromQrUrl(url);
    if (session == null) return null;
    
    if (session.isExpired) {
      debugPrint('QuickTransfer: 二维码已过期');
      return null;
    }
    
    return Device(
      name: session.name,
      ip: session.ip,
      port: session.port,
      syncPort: session.port,
      requiresPassword: false,
      salt: '',
    );
  }
  
  /// 清理资源
  void dispose() {
    stopSession();
  }
}
