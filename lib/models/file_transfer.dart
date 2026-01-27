import 'dart:convert';

/// 传输方向
enum TransferDirection {
  send,    // 发送
  receive, // 接收
}

/// 传输状态
enum TransferStatus {
  pending,     // 等待中
  connecting,  // 连接中
  transferring,// 传输中
  paused,      // 已暂停
  completed,   // 已完成
  failed,      // 失败
  cancelled,   // 已取消
}

/// 文件传输任务模型
class FileTransferTask {
  final String id;                    // 唯一标识
  final String fileName;              // 文件名
  final int fileSize;                 // 文件大小(字节)
  final TransferDirection direction;  // 传输方向
  final String peerId;                // 对端设备标识(IP:Port)
  final String peerName;              // 对端设备名称
  final String localPath;             // 本地文件路径
  final DateTime createdAt;           // 创建时间
  
  TransferStatus status;              // 当前状态
  int transferredBytes;               // 已传输字节数
  int currentChunk;                   // 当前块索引
  int totalChunks;                    // 总块数
  double speed;                       // 传输速度(字节/秒)
  String? error;                      // 错误信息
  DateTime? completedAt;              // 完成时间

  FileTransferTask({
    required this.id,
    required this.fileName,
    required this.fileSize,
    required this.direction,
    required this.peerId,
    required this.peerName,
    required this.localPath,
    DateTime? createdAt,
    this.status = TransferStatus.pending,
    this.transferredBytes = 0,
    this.currentChunk = 0,
    this.totalChunks = 0,
    this.speed = 0,
    this.error,
    this.completedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 进度百分比 (0.0 - 1.0)
  double get progress => fileSize > 0 ? transferredBytes / fileSize : 0;

  /// 格式化文件大小
  String get formattedSize => _formatBytes(fileSize);

  /// 格式化已传输大小
  String get formattedTransferred => _formatBytes(transferredBytes);

  /// 格式化速度
  String get formattedSpeed => '${_formatBytes(speed.toInt())}/s';

  /// 预计剩余时间(秒)
  int get estimatedRemainingSeconds {
    if (speed <= 0) return 0;
    final remaining = fileSize - transferredBytes;
    return (remaining / speed).ceil();
  }

  /// 格式化剩余时间
  String get formattedRemainingTime {
    final seconds = estimatedRemainingSeconds;
    if (seconds <= 0) return '--';
    if (seconds < 60) return '$seconds秒';
    if (seconds < 3600) return '${seconds ~/ 60}分${seconds % 60}秒';
    return '${seconds ~/ 3600}时${(seconds % 3600) ~/ 60}分';
  }

  /// 是否可以暂停
  bool get canPause => status == TransferStatus.transferring;

  /// 是否可以恢复
  bool get canResume => status == TransferStatus.paused || status == TransferStatus.failed;

  /// 是否可以取消
  bool get canCancel => status == TransferStatus.pending || 
                        status == TransferStatus.connecting ||
                        status == TransferStatus.transferring || 
                        status == TransferStatus.paused;

  /// 是否活跃中
  bool get isActive => status == TransferStatus.pending ||
                       status == TransferStatus.connecting ||
                       status == TransferStatus.transferring ||
                       status == TransferStatus.paused;

  /// 复制并更新
  FileTransferTask copyWith({
    TransferStatus? status,
    int? transferredBytes,
    int? currentChunk,
    int? totalChunks,
    double? speed,
    String? error,
    DateTime? completedAt,
  }) {
    return FileTransferTask(
      id: id,
      fileName: fileName,
      fileSize: fileSize,
      direction: direction,
      peerId: peerId,
      peerName: peerName,
      localPath: localPath,
      createdAt: createdAt,
      status: status ?? this.status,
      transferredBytes: transferredBytes ?? this.transferredBytes,
      currentChunk: currentChunk ?? this.currentChunk,
      totalChunks: totalChunks ?? this.totalChunks,
      speed: speed ?? this.speed,
      error: error ?? this.error,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  /// 序列化为 Map (用于断点续传持久化)
  Map<String, dynamic> toJson() => {
    'id': id,
    'fileName': fileName,
    'fileSize': fileSize,
    'direction': direction.index,
    'peerId': peerId,
    'peerName': peerName,
    'localPath': localPath,
    'createdAt': createdAt.toIso8601String(),
    'status': status.index,
    'transferredBytes': transferredBytes,
    'currentChunk': currentChunk,
    'totalChunks': totalChunks,
  };

  /// 从 Map 反序列化
  factory FileTransferTask.fromJson(Map<String, dynamic> json) {
    return FileTransferTask(
      id: json['id'],
      fileName: json['fileName'],
      fileSize: json['fileSize'],
      direction: TransferDirection.values[json['direction']],
      peerId: json['peerId'],
      peerName: json['peerName'],
      localPath: json['localPath'],
      createdAt: DateTime.parse(json['createdAt']),
      status: TransferStatus.values[json['status']],
      transferredBytes: json['transferredBytes'],
      currentChunk: json['currentChunk'],
      totalChunks: json['totalChunks'],
    );
  }

  /// 格式化字节数
  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}

/// 文件传输元数据 (传输协议头)
class FileTransferMeta {
  final String taskId;         // 任务ID
  final String fileName;       // 文件名
  final int fileSize;          // 文件大小
  final int totalChunks;       // 总块数
  final int chunkSize;         // 块大小
  final String checksum;       // 文件校验和(MD5)
  final int resumeFromChunk;   // 从第几块开始(断点续传)

  FileTransferMeta({
    required this.taskId,
    required this.fileName,
    required this.fileSize,
    required this.totalChunks,
    required this.chunkSize,
    required this.checksum,
    this.resumeFromChunk = 0,
  });

  /// 序列化为 JSON 字符串
  String toJsonString() {
    // 使用标准 JSON 编码，避免特殊字符破坏格式
    return jsonEncode({
      'taskId': taskId,
      'fileName': fileName,
      'fileSize': fileSize,
      'totalChunks': totalChunks,
      'chunkSize': chunkSize,
      'checksum': checksum,
      'resumeFromChunk': resumeFromChunk,
    });
  }

  /// 从 JSON 字符串解析
  factory FileTransferMeta.fromJsonString(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) {
        return FileTransferMeta(
          taskId: decoded['taskId']?.toString() ?? '',
          fileName: decoded['fileName']?.toString() ?? '',
          fileSize: _parseInt(decoded['fileSize']),
          totalChunks: _parseInt(decoded['totalChunks']),
          chunkSize: _parseInt(decoded['chunkSize']),
          checksum: decoded['checksum']?.toString() ?? '',
          resumeFromChunk: _parseInt(decoded['resumeFromChunk']),
        );
      }
    } catch (_) {
      // 解析失败时返回空元数据
    }
    return FileTransferMeta(
      taskId: '',
      fileName: '',
      fileSize: 0,
      totalChunks: 0,
      chunkSize: 0,
      checksum: '',
      resumeFromChunk: 0,
    );
  }

  // 解析数值，兼容 int/num/String
  static int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}

/// 传输协议消息类型
class TransferProtocol {
  // 消息类型前缀
  static const String prefixMeta = 'FILE_META:';        // 文件元数据
  static const String prefixAccept = 'FILE_ACCEPT:';    // 接受传输
  static const String prefixReject = 'FILE_REJECT:';    // 拒绝传输
  static const String prefixChunk = 'FILE_CHUNK:';      // 数据块
  static const String prefixAck = 'FILE_ACK:';          // 确认收到
  static const String prefixComplete = 'FILE_COMPLETE:';// 传输完成
  static const String prefixCancel = 'FILE_CANCEL:';    // 取消传输
  static const String prefixResume = 'FILE_RESUME:';    // 请求续传
  
  // 默认块大小: 64KB
  static const int defaultChunkSize = 64 * 1024;
  
  // 文件传输端口
  static const int fileTransferPort = 8890;
}
