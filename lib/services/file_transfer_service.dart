import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/file_transfer.dart';
import '../models/device.dart';
import 'encryption_service.dart';
import 'package:cryptography/cryptography.dart' as crypto;

/// 文件传输服务
/// 负责文件的发送和接收，支持分块传输和断点续传
class FileTransferService {
  static const String _downloadPathKey = 'file_download_path';
  static const String _pendingTasksKey = 'pending_transfer_tasks';
  static const String _autoAcceptKey = 'file_transfer_auto_accept';
  
  // 单例模式
  static final FileTransferService _instance = FileTransferService._internal();
  factory FileTransferService() => _instance;
  FileTransferService._internal();

  // TCP 服务器
  ServerSocket? _server;
  
  // 传输任务列表
  final List<FileTransferTask> _tasks = [];
  
  // 任务变更通知
  final _taskController = StreamController<List<FileTransferTask>>.broadcast();
  Stream<List<FileTransferTask>> get taskStream => _taskController.stream;
  
  // 新任务请求通知(接收方收到传输请求)
  final _requestController = StreamController<FileTransferTask>.broadcast();
  Stream<FileTransferTask> get requestStream => _requestController.stream;
  
  // 加密设置
  bool _encryptionEnabled = false;
  crypto.SecretKey? _encryptionKey;
  
  // 活跃的传输连接
  final Map<String, Socket> _activeConnections = {};
  final Map<String, StreamSubscription> _activeSubscriptions = {};
  final Map<String, FileTransferMeta> _pendingMeta = {};
  
  // 速度计算
  final Map<String, int> _lastTransferredBytes = {};
  final Map<String, DateTime> _lastSpeedUpdate = {};

  /// 获取所有任务
  List<FileTransferTask> get tasks => List.unmodifiable(_tasks);
  
  /// 获取活跃任务数
  int get activeTaskCount => _tasks.where((t) => t.isActive).length;

  /// 设置加密
  void setEncryption({required bool enabled, crypto.SecretKey? key}) {
    if (enabled && key == null) {
      _encryptionEnabled = false;
      _encryptionKey = null;
      return;
    }
    _encryptionEnabled = enabled;
    _encryptionKey = key;
  }

  /// 启动文件传输服务器
  Future<int> startServer() async {
    await _server?.close();
    _server = await ServerSocket.bind(
      InternetAddress.anyIPv4, 
      TransferProtocol.fileTransferPort,
    );
    
    _server!.listen(_handleIncomingConnection);
    
    // 恢复未完成的任务
    await _loadPendingTasks();
    
    return _server!.port;
  }

  /// 获取自动接收设置
  Future<bool> isAutoAcceptEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoAcceptKey) ?? false;
  }

  /// 设置自动接收
  Future<void> setAutoAcceptEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoAcceptKey, enabled);
  }

  /// 处理入站连接
  void _handleIncomingConnection(Socket socket) {
    String? currentTaskId;
    FileTransferTask? currentTask;
    RandomAccessFile? fileHandle;

    // 缓冲区：按字节解析，避免二进制数据损坏
    List<int> buffer = [];
    late StreamSubscription subscription;

    void trackConnection() {
      if (currentTaskId != null && !_activeConnections.containsKey(currentTaskId)) {
        _activeConnections[currentTaskId!] = socket;
        _activeSubscriptions[currentTaskId!] = subscription;
      }
    }

    subscription = socket.listen(
      (Uint8List data) async {
        try {
          buffer.addAll(data);

          while (true) {
            final newlineIndex = buffer.indexOf(10);
            if (newlineIndex == -1) break;

            final headerBytes = buffer.sublist(0, newlineIndex);
            final headerLine = utf8.decode(headerBytes, allowMalformed: true);

            // 处理数据块（需要完整头+数据）
            if (headerLine.startsWith(TransferProtocol.prefixChunk)) {
              final header = headerLine.substring(TransferProtocol.prefixChunk.length);
              final parts = header.split(':');
              if (parts.length < 3) {
                buffer = buffer.sublist(newlineIndex + 1);
                continue;
              }

              final chunkIndex = int.tryParse(parts[1]) ?? 0;
              final dataLength = int.tryParse(parts[2]) ?? 0;
              final dataStart = newlineIndex + 1;

              // 数据未完整时等待下一次
              if (buffer.length < dataStart + dataLength) break;

              final chunkData = Uint8List.fromList(
                buffer.sublist(dataStart, dataStart + dataLength),
              );
              buffer = buffer.sublist(dataStart + dataLength);

              if (currentTask == null) {
                // 未建立任务时丢弃数据块
                continue;
              }

              // 打开文件(首次)
              fileHandle ??= await File(currentTask!.localPath)
                  .open(mode: FileMode.writeOnlyAppend);

              // 解密数据(如果启用)
              Uint8List dataToWrite = chunkData;
              if (_encryptionEnabled) {
                if (_encryptionKey == null) {
                  currentTask = currentTask!.copyWith(
                    status: TransferStatus.failed,
                    error: '缺少解密密钥',
                  );
                  _updateTask(currentTask!);
                  await fileHandle?.close();
                  fileHandle = null;
                  socket.close();
                  return;
                }

                final decrypted = await EncryptionService.decryptBytes(
                  chunkData,
                  _encryptionKey!,
                );
                if (decrypted == null) {
                  currentTask = currentTask!.copyWith(
                    status: TransferStatus.failed,
                    error: '解密失败',
                  );
                  _updateTask(currentTask!);
                  await fileHandle?.close();
                  fileHandle = null;
                  socket.close();
                  return;
                }
                dataToWrite = decrypted;
              }

              // 写入数据
              await fileHandle!.writeFrom(dataToWrite);

              // 更新进度
              currentTask = currentTask!.copyWith(
                status: TransferStatus.transferring,
                currentChunk: chunkIndex + 1,
                transferredBytes: currentTask!.transferredBytes + dataToWrite.length,
              );
              _updateTask(currentTask!);
              _updateSpeed(currentTask!.id, currentTask!.transferredBytes);

              // 发送确认
              socket.write('${TransferProtocol.prefixAck}${currentTask!.id}:$chunkIndex\n');

              // 检查是否完成
              if (currentTask!.currentChunk >= currentTask!.totalChunks) {
                await fileHandle!.close();
                fileHandle = null;

                currentTask = currentTask!.copyWith(
                  status: TransferStatus.completed,
                  completedAt: DateTime.now(),
                );
                _updateTask(currentTask!);
                socket.write('${TransferProtocol.prefixComplete}${currentTask!.id}\n');
              }
              continue;
            }

            // 非数据块消息，移除头部
            buffer = buffer.sublist(newlineIndex + 1);

            // 处理元数据消息
            if (headerLine.startsWith(TransferProtocol.prefixMeta)) {
              final metaJson = headerLine.substring(TransferProtocol.prefixMeta.length);
              final meta = FileTransferMeta.fromJsonString(metaJson);

              // 创建接收任务
              final downloadPath = await getDownloadPath();
              final localPath = '$downloadPath/${meta.fileName}';

              currentTask = FileTransferTask(
                id: meta.taskId,
                fileName: meta.fileName,
                fileSize: meta.fileSize,
                direction: TransferDirection.receive,
                peerId: '${socket.remoteAddress.address}:${socket.remotePort}',
                peerName: 'Remote',
                localPath: localPath,
                status: TransferStatus.pending,
                totalChunks: meta.totalChunks,
              );
              currentTaskId = meta.taskId;

            // 添加到任务列表
            _tasks.add(currentTask!);
            _notifyTasksChanged();

            // 追踪连接，支持取消/清理
            trackConnection();

            // 保存元数据，等待用户确认
            _pendingMeta[currentTaskId!] = meta;

            // 发送接收请求通知
            _requestController.add(currentTask!);

            // 自动接受(若开启)
            final autoAccept = await isAutoAcceptEnabled();
            if (autoAccept) {
              await acceptTask(currentTaskId!);
            }
            continue;
          }

            // 处理取消消息
            if (headerLine.startsWith(TransferProtocol.prefixCancel)) {
              if (currentTask != null) {
                await fileHandle?.close();
                fileHandle = null;
                currentTask = currentTask!.copyWith(status: TransferStatus.cancelled);
                _updateTask(currentTask!);
              }
              continue;
            }
          }
        } catch (e) {
          // 解析或处理失败时标记任务失败
          if (currentTask != null) {
            currentTask = currentTask!.copyWith(
              status: TransferStatus.failed,
              error: e.toString(),
            );
            _updateTask(currentTask!);
          }
        }
      },
      onError: (e) async {
        await fileHandle?.close();
        if (currentTask != null) {
          currentTask = currentTask!.copyWith(
            status: TransferStatus.failed,
            error: e.toString(),
          );
          _updateTask(currentTask!);
        }
      },
      onDone: () async {
        await fileHandle?.close();
        if (currentTaskId != null) {
          _activeConnections.remove(currentTaskId);
          _activeSubscriptions.remove(currentTaskId);
          _pendingMeta.remove(currentTaskId);
        }
      },
    );
  }

  /// 接受传输（确保目录存在）
  void _acceptTransfer(Socket socket, FileTransferTask task, FileTransferMeta meta) async {
    // 确保下载目录存在
    final dir = Directory(task.localPath).parent;
    if (!await dir.exists()) {
      try {
        await dir.create(recursive: true);
      } catch (_) {
        // 目录创建失败，取消传输
        socket.write('${TransferProtocol.prefixReject}${task.id}\n');
        _updateTask(task.copyWith(status: TransferStatus.failed));
        return;
      }
    }
    
    // 检查是否存在部分文件(断点续传)
    final file = File(task.localPath);
    int resumeFrom = 0;
    
    if (file.existsSync()) {
      final existingSize = file.lengthSync();
      resumeFrom = existingSize ~/ meta.chunkSize;
    }
    
    // 发送接受消息
    socket.write('${TransferProtocol.prefixAccept}${task.id}:$resumeFrom\n');
    
    // 更新任务状态
    final updatedTask = task.copyWith(
      status: TransferStatus.connecting,
      currentChunk: resumeFrom,
      transferredBytes: resumeFrom * meta.chunkSize,
    );
    _updateTask(updatedTask);
  }

  /// 用户确认接收
  Future<void> acceptTask(String taskId) async {
    final meta = _pendingMeta[taskId];
    final index = _tasks.indexWhere((t) => t.id == taskId);
    final socket = _activeConnections[taskId];
    if (meta == null || index == -1 || socket == null) return;

    _pendingMeta.remove(taskId);
    _acceptTransfer(socket, _tasks[index], meta);
  }

  /// 用户拒绝接收
  Future<void> rejectTask(String taskId) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;

    final socket = _activeConnections[taskId];
    if (socket != null) {
      socket.write('${TransferProtocol.prefixReject}$taskId\n');
      await socket.flush();
      await socket.close();
    }

    _activeConnections.remove(taskId);
    await _activeSubscriptions[taskId]?.cancel();
    _activeSubscriptions.remove(taskId);
    _pendingMeta.remove(taskId);

    _tasks[index] = _tasks[index].copyWith(status: TransferStatus.cancelled);
    _notifyTasksChanged();
  }

  /// 发送文件到指定设备
  Future<FileTransferTask?> sendFile({
    required String filePath,
    required Device device,
    String? passwordHash,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) return null;
    
    final fileSize = await file.length();
    final fileName = file.uri.pathSegments.last;
    final taskId = const Uuid().v4();
    final totalChunks = (fileSize / TransferProtocol.defaultChunkSize).ceil();
    
    // 计算文件校验和
    final checksum = await _calculateChecksum(file);
    
    // 创建任务
    final task = FileTransferTask(
      id: taskId,
      fileName: fileName,
      fileSize: fileSize,
      direction: TransferDirection.send,
      peerId: '${device.ip}:${TransferProtocol.fileTransferPort}',
      peerName: device.name,
      localPath: filePath,
      status: TransferStatus.connecting,
      totalChunks: totalChunks,
    );
    
    _tasks.add(task);
    _notifyTasksChanged();
    
    // 开始传输
    _startSendingFile(task, device, checksum);
    
    return task;
  }

  /// 批量发送文件
  Future<List<FileTransferTask>> sendFiles({
    required List<String> filePaths,
    required Device device,
    String? passwordHash,
  }) async {
    final tasks = <FileTransferTask>[];
    for (final path in filePaths) {
      final task = await sendFile(
        filePath: path,
        device: device,
        passwordHash: passwordHash,
      );
      if (task != null) {
        tasks.add(task);
      }
    }
    return tasks;
  }

  /// 开始发送文件
  Future<void> _startSendingFile(
    FileTransferTask task, 
    Device device, 
    String checksum,
  ) async {
    try {
      final socket = await Socket.connect(
        device.ip,
        TransferProtocol.fileTransferPort,
        timeout: const Duration(seconds: 10),
      );
      
      _activeConnections[task.id] = socket;
      
      // 发送元数据
      final meta = FileTransferMeta(
        taskId: task.id,
        fileName: task.fileName,
        fileSize: task.fileSize,
        totalChunks: task.totalChunks,
        chunkSize: TransferProtocol.defaultChunkSize,
        checksum: checksum,
      );
      
      socket.write('${TransferProtocol.prefixMeta}${meta.toJsonString()}\n');
      
      // 监听响应
      final subscription = socket.listen(
        (data) async {
          final message = utf8.decode(data);
          
          // 处理接受消息
          if (message.startsWith(TransferProtocol.prefixAccept)) {
            final parts = message.substring(TransferProtocol.prefixAccept.length).trim().split(':');
            int resumeFromChunk = 0;
            if (parts.length >= 2) {
              resumeFromChunk = int.tryParse(parts[1]) ?? 0;
            }
            
            // 开始发送数据块
            await _sendFileChunks(socket, task, resumeFromChunk);
          }
          
          // 处理完成消息
          if (message.startsWith(TransferProtocol.prefixComplete)) {
            final updatedTask = task.copyWith(
              status: TransferStatus.completed,
              completedAt: DateTime.now(),
            );
            _updateTask(updatedTask);
            socket.close();
          }
          
          // 处理拒绝消息
          if (message.startsWith(TransferProtocol.prefixReject)) {
            final updatedTask = task.copyWith(
              status: TransferStatus.failed,
              error: '对方拒绝接收',
            );
            _updateTask(updatedTask);
            socket.close();
          }
        },
        onError: (e) {
          final updatedTask = task.copyWith(
            status: TransferStatus.failed,
            error: e.toString(),
          );
          _updateTask(updatedTask);
        },
        onDone: () {
          _activeConnections.remove(task.id);
          _activeSubscriptions.remove(task.id);
        },
      );
      
      _activeSubscriptions[task.id] = subscription;
      
    } catch (e) {
      final updatedTask = task.copyWith(
        status: TransferStatus.failed,
        error: '连接失败: $e',
      );
      _updateTask(updatedTask);
    }
  }

  /// 发送文件数据块
  Future<void> _sendFileChunks(Socket socket, FileTransferTask task, int startChunk) async {
    final file = File(task.localPath);
    final fileHandle = await file.open();
    
    try {
      var updatedTask = task.copyWith(
        status: TransferStatus.transferring,
        currentChunk: startChunk,
        transferredBytes: startChunk * TransferProtocol.defaultChunkSize,
      );
      _updateTask(updatedTask);
      
      // 跳到断点位置
      await fileHandle.setPosition(startChunk * TransferProtocol.defaultChunkSize);
      
      for (int i = startChunk; i < task.totalChunks; i++) {
        // 检查任务状态
        final currentIndex = _tasks.indexWhere((t) => t.id == task.id);
        if (currentIndex == -1) {
          // 任务可能已被移除
          break;
        }
        final currentTask = _tasks[currentIndex];
        if (currentTask.status == TransferStatus.cancelled ||
            currentTask.status == TransferStatus.paused) {
          break;
        }
        
        // 读取数据块
        final chunkData = await fileHandle.read(TransferProtocol.defaultChunkSize);
        
        // 加密数据(如果启用)
        Uint8List dataToSend = chunkData;
        if (_encryptionEnabled && _encryptionKey != null) {
          final encrypted = await EncryptionService.encryptBytes(chunkData, _encryptionKey!);
          dataToSend = encrypted;
        }
        
        // 发送块头和数据
        final header = '${TransferProtocol.prefixChunk}${task.id}:$i:${dataToSend.length}\n';
        socket.add(utf8.encode(header));
        socket.add(dataToSend);
        await socket.flush();
        
        // 更新进度
        updatedTask = updatedTask.copyWith(
          currentChunk: i + 1,
          transferredBytes: updatedTask.transferredBytes + chunkData.length,
        );
        _updateTask(updatedTask);
        _updateSpeed(updatedTask.id, updatedTask.transferredBytes);
        
        // 小延迟，避免网络拥塞
        await Future.delayed(const Duration(milliseconds: 1));
      }
    } finally {
      await fileHandle.close();
    }
  }

  /// 计算文件校验和
  Future<String> _calculateChecksum(File file) async {
    // 流式计算，避免大文件占用内存
    final digest = await md5.bind(file.openRead()).first;
    return digest.toString();
  }

  /// 更新传输速度
  void _updateSpeed(String taskId, int currentBytes) {
    final now = DateTime.now();
    final lastBytes = _lastTransferredBytes[taskId] ?? 0;
    final lastTime = _lastSpeedUpdate[taskId];
    
    if (lastTime != null) {
      final elapsed = now.difference(lastTime).inMilliseconds;
      if (elapsed > 500) { // 每500ms更新一次
        final speed = (currentBytes - lastBytes) * 1000 / elapsed;
        final index = _tasks.indexWhere((t) => t.id == taskId);
        if (index == -1) return;
        final task = _tasks[index];
        _updateTask(task.copyWith(speed: speed));
        
        _lastTransferredBytes[taskId] = currentBytes;
        _lastSpeedUpdate[taskId] = now;
      }
    } else {
      _lastTransferredBytes[taskId] = currentBytes;
      _lastSpeedUpdate[taskId] = now;
    }
  }

  /// 暂停传输
  void pauseTask(String taskId) {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index != -1) {
      _tasks[index] = _tasks[index].copyWith(status: TransferStatus.paused);
      _notifyTasksChanged();
      _savePendingTasks();
    }
  }

  /// 恢复传输
  Future<void> resumeTask(String taskId, Device device) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index != -1) {
      final task = _tasks[index];
      if (task.direction == TransferDirection.send) {
        final checksum = await _calculateChecksum(File(task.localPath));
        _startSendingFile(task, device, checksum);
      }
      // 接收方的恢复由发送方触发
    }
  }

  /// 取消传输
  void cancelTask(String taskId) {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index != -1) {
      _tasks[index] = _tasks[index].copyWith(status: TransferStatus.cancelled);
      _notifyTasksChanged();
      
      // 关闭连接
      _activeConnections[taskId]?.close();
      _activeSubscriptions[taskId]?.cancel();
      _activeConnections.remove(taskId);
      _activeSubscriptions.remove(taskId);
    }
  }

  /// 删除任务(仅从列表移除)
  void removeTask(String taskId) {
    _tasks.removeWhere((t) => t.id == taskId);
    _notifyTasksChanged();
    
    // 清理速度记录
    _lastTransferredBytes.remove(taskId);
    _lastSpeedUpdate.remove(taskId);
  }

  /// 清空已完成的任务
  void clearCompletedTasks() {
    _tasks.removeWhere((t) => 
      t.status == TransferStatus.completed || 
      t.status == TransferStatus.cancelled ||
      t.status == TransferStatus.failed
    );
    _notifyTasksChanged();
  }

  /// 更新任务
  void _updateTask(FileTransferTask task) {
    final index = _tasks.indexWhere((t) => t.id == task.id);
    if (index != -1) {
      _tasks[index] = task;
      _notifyTasksChanged();
    }
  }

  /// 通知任务列表变更
  void _notifyTasksChanged() {
    _taskController.add(List.unmodifiable(_tasks));
  }

  /// 获取下载路径（不自动创建目录）
  Future<String> getDownloadPath() async {
    final prefs = await SharedPreferences.getInstance();
    final customPath = prefs.getString(_downloadPathKey);
    
    if (customPath != null && await Directory(customPath).exists()) {
      return customPath;
    }
    
    // 默认路径
    String basePath;
    if (Platform.isAndroid) {
      // Android: 使用外部存储的 Download 目录
      basePath = '/storage/emulated/0/Download';
    } else if (Platform.isWindows) {
      // Windows: 使用用户下载目录
      final userProfile = Platform.environment['USERPROFILE'] ?? '';
      basePath = '$userProfile\\Downloads';
    } else if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '';
      basePath = '$home/Downloads';
    } else {
      // Linux 及其他
      final home = Platform.environment['HOME'] ?? '';
      basePath = '$home/Downloads';
    }
    
    return '$basePath/LanClip';
  }
  
  /// 确保下载目录存在（需要存储权限时调用）
  Future<bool> ensureDownloadDirExists() async {
    final downloadPath = await getDownloadPath();
    final dir = Directory(downloadPath);
    if (!await dir.exists()) {
      try {
        await dir.create(recursive: true);
        return true;
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  /// 设置下载路径
  Future<void> setDownloadPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_downloadPathKey, path);
  }

  /// 获取缓存大小
  Future<int> getCacheSize() async {
    final downloadPath = await getDownloadPath();
    final dir = Directory(downloadPath);
    
    if (!await dir.exists()) return 0;
    
    int totalSize = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        totalSize += await entity.length();
      }
    }
    return totalSize;
  }

  /// 清理缓存(清空下载目录)
  Future<void> clearCache() async {
    final downloadPath = await getDownloadPath();
    final dir = Directory(downloadPath);
    
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File) {
          await entity.delete();
        }
      }
    }
  }

  /// 保存未完成的任务(断点续传)
  Future<void> _savePendingTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final pendingTasks = _tasks
        .where((t) => t.status == TransferStatus.paused)
        .map((t) => t.toJson())
        .toList();
    await prefs.setString(_pendingTasksKey, jsonEncode(pendingTasks));
  }

  /// 加载未完成的任务
  Future<void> _loadPendingTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_pendingTasksKey);
    if (json != null) {
      try {
        final List<dynamic> list = jsonDecode(json);
        for (final item in list) {
          final task = FileTransferTask.fromJson(item);
          if (!_tasks.any((t) => t.id == task.id)) {
            _tasks.add(task);
          }
        }
        _notifyTasksChanged();
      } catch (e) {
        // 解析失败，忽略
      }
    }
  }

  /// 停止服务
  void dispose() {
    _server?.close();
    _taskController.close();
    _requestController.close();
    
    for (final socket in _activeConnections.values) {
      socket.close();
    }
    for (final sub in _activeSubscriptions.values) {
      sub.cancel();
    }
    _activeConnections.clear();
    _activeSubscriptions.clear();
  }
}
