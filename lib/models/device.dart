/// 设备信息模型
class Device {
  final String ip;
  final int port;
  final String name;
  final bool requiresPassword;  // 是否需要密码
  final DateTime discoveredAt;

  Device({
    required this.ip,
    required this.port,
    required this.name,
    this.requiresPassword = false,
    DateTime? discoveredAt,
  }) : discoveredAt = discoveredAt ?? DateTime.now();

  /// 从 UDP 发现响应解析设备信息
  /// 响应格式: "LAN_CLIP|{name}|{port}|{requiresPassword:0/1}"
  factory Device.fromDiscoveryResponse(String response, String ip) {
    final parts = response.split('|');
    if (parts.length >= 3 && parts[0] == 'LAN_CLIP') {
      return Device(
        ip: ip,
        name: parts[1],
        port: int.tryParse(parts[2]) ?? 8888,
        requiresPassword: parts.length >= 4 && parts[3] == '1',
      );
    }
    return Device(ip: ip, name: 'Unknown', port: 8888);
  }

  @override
  String toString() => '$name ($ip:$port)${requiresPassword ? ' [需密码]' : ''}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Device && ip == other.ip && port == other.port;

  @override
  int get hashCode => ip.hashCode ^ port.hashCode;
}
