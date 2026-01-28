import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cryptography/cryptography.dart';

import '../models/device.dart';
import '../models/clipboard_data.dart';
import '../models/file_transfer.dart';
import '../services/auth_service.dart';
import '../services/clipboard_service.dart'
    show
        cmdBackspace,
        cmdSpace,
        cmdClear,
        cmdEnter,
        cmdArrowUp,
        cmdArrowDown,
        cmdArrowLeft,
        cmdArrowRight,
        cmdShutdown,
        cmdShutdownCancel,
        cmdShutdownNow;
import '../services/clipboard_sync_service.dart';
import '../services/discovery_service.dart';
import '../services/encryption_service.dart';
import '../services/file_transfer_service.dart';
import '../services/input_method_service.dart';
import '../services/mobile_clipboard_helper.dart';
import '../services/socket_service.dart';
import '../services/storage_permission_service.dart';
import '../services/text_memory_service.dart';
import 'app_grid_screen.dart';
import 'file_transfer_screen.dart';
import 'settings_screen.dart';
import 'simple_input_screen.dart';
import 'text_memory_screen.dart';
import 'touchpad_screen.dart';

part 'mobile_screen_actions.dart';
part 'mobile_screen_dialogs.dart';
part 'mobile_screen_ui.dart';

// 自动发送设置的存储键
const String _autoSendEnabledKey = 'auto_send_enabled';
const String _autoSendDelayKey = 'auto_send_delay';
const String _receiveFromPcKey = 'receive_from_pc_enabled';

/// 手机端界面 - 输入内容并发送到电脑
class MobileScreen extends StatefulWidget {
  const MobileScreen({super.key});

  @override
  State<MobileScreen> createState() => _MobileScreenState();
}

class _MobileScreenState extends State<MobileScreen> {
  final _textController = TextEditingController();
  final _discoveryService = DiscoveryService();
  final _socketService = SocketService();
  final _clipboardSyncService = ClipboardSyncService();
  final _fileTransferService = FileTransferService();
  final _inputFocusNode = FocusNode();
  final _textMemoryService = TextMemoryService();

  final List<Device> _devices = [];
  Device? _selectedDevice;
  bool _isSearching = false;
  bool _isSending = false;
  bool _receiveFromPc = false;
  int _syncPort = 0;
  int _activeTransferCount = 0;
  bool _encryptionEnabled = false;
  SecretKey? _encryptionKey;

  // 存储设备对应的密码哈希（用户输入后缓存）
  final Map<String, String> _devicePasswords = {};

  StreamSubscription<Device>? _deviceSubscription;
  StreamSubscription<ClipboardContent>? _syncSubscription;
  StreamSubscription<List<FileTransferTask>>? _transferSubscription;
  StreamSubscription<FileTransferTask>? _transferRequestSubscription;

  // 自动发送相关状态
  bool _autoSendEnabled = false;
  double _autoSendDelay = 3.0;
  Timer? _autoSendTimer;
  int _countdownSeconds = 0;
  Timer? _countdownTimer;
  Timer? _longPressTimer;

  int _memoryCount = 0;

  @override
  void initState() {
    super.initState();
    _initialize();

    _deviceSubscription = _discoveryService.deviceStream.listen((device) {
      setState(() {
        if (!_devices.contains(device)) {
          _devices.add(device);
        }
        _selectedDevice ??= device;
      });
    });

    _syncSubscription = _clipboardSyncService.contentStream.listen((content) {
      _onClipboardReceived(content);
    });

    _textController.addListener(_onTextChanged);

    _initFileTransfer();
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _inputFocusNode.dispose();
    _deviceSubscription?.cancel();
    _syncSubscription?.cancel();
    _transferSubscription?.cancel();
    _transferRequestSubscription?.cancel();
    _discoveryService.dispose();
    _socketService.dispose();
    _clipboardSyncService.dispose();
    _fileTransferService.dispose();
    _cancelAutoSendTimer();
    _longPressTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return buildMobileScreen(context);
  }
}
