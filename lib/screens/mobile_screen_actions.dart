part of 'mobile_screen.dart';

extension _MobileScreenStateActions on _MobileScreenState {
  /// 初始化：加载设置 -> 搜索设备
  Future<void> _initialize() async {
    await _loadSettings();
    await _loadMemoryCount();
    if (mounted) {
      _searchDevices();
    }
  }

  Future<void> _initFileTransfer() async {
    // Android: 请求存储权限
    if (Platform.isAndroid) {
      await StoragePermissionService.requestPermission(context);
    }

    await _fileTransferService.startServer();
    _fileTransferService.setEncryption(enabled: _encryptionEnabled, key: _encryptionKey);
    _transferSubscription = _fileTransferService.taskStream.listen((tasks) {
      if (mounted) {
        setState(() {
          _activeTransferCount = tasks.where((t) => t.isActive).length;
        });
      }
    });

    // 监听传输请求
    _transferRequestSubscription = _fileTransferService.requestStream.listen((task) async {
      final autoAccept = await _fileTransferService.isAutoAcceptEnabled();
      if (autoAccept) {
        if (mounted) {
          _showSnackBar('已自动接收 ${task.fileName}');
        }
        return;
      }
      if (mounted) {
        _showIncomingFileDialog(task);
      }
    });
  }

  Future<void> _loadMemoryCount() async {
    final count = await _textMemoryService.getCount();
    if (mounted) {
      setState(() => _memoryCount = count);
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final receiveFromPc = prefs.getBool(_receiveFromPcKey) ?? false;
    final passwordEnabled = await AuthService.isPasswordEnabled();
    final encryptionEnabled = await EncryptionService.isEncryptionEnabled();
    var effectiveEncryptionEnabled = encryptionEnabled;
    var resetEncryption = false;

    // 未启用密码时强制关闭加密，避免解密失败
    if (encryptionEnabled && !passwordEnabled) {
      await EncryptionService.setEncryptionEnabled(false);
      effectiveEncryptionEnabled = false;
      resetEncryption = true;
    }

    setState(() {
      _autoSendEnabled = prefs.getBool(_autoSendEnabledKey) ?? false;
      _autoSendDelay = prefs.getDouble(_autoSendDelayKey) ?? 3.0;
      _receiveFromPc = receiveFromPc;
      _encryptionEnabled = effectiveEncryptionEnabled;
    });
    _fileTransferService.setEncryption(enabled: _encryptionEnabled, key: _encryptionKey);

    if (resetEncryption && mounted) {
      _showSnackBar('未设置密码，已关闭加密');
    }

    if (receiveFromPc) {
      await _startSyncService();
    }
  }

  /// 输入变化时的回调
  void _onTextChanged() {
    if (!_autoSendEnabled) return;

    _cancelAutoSendTimer();

    final content = _textController.text.trimRight();
    if (content.trim().isEmpty || _selectedDevice == null || _isSending) {
      return;
    }

    _countdownSeconds = _autoSendDelay.ceil();
    setState(() {});

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _countdownSeconds--;
      });
      if (_countdownSeconds <= 0) {
        timer.cancel();
      }
    });

    _autoSendTimer = Timer(Duration(milliseconds: (_autoSendDelay * 1000).toInt()), () {
      _countdownTimer?.cancel();
      setState(() {
        _countdownSeconds = 0;
      });
      _sendContent();
    });
  }

  /// 取消自动发送计时器
  void _cancelAutoSendTimer() {
    _autoSendTimer?.cancel();
    _autoSendTimer = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    if (_countdownSeconds > 0) {
      setState(() {
        _countdownSeconds = 0;
      });
    }
  }

  /// 启动剪贴板同步服务
  Future<void> _startSyncService() async {
    _clipboardSyncService.setEncryption(enabled: _encryptionEnabled, key: _encryptionKey);
    final port = await _clipboardSyncService.startServer();
    setState(() => _syncPort = port);
  }

  /// 停止剪贴板同步服务
  Future<void> _stopSyncService() async {
    await _clipboardSyncService.stopServer();
    setState(() => _syncPort = 0);
  }

  /// 处理接收到的电脑剪贴板内容
  Future<void> _onClipboardReceived(ClipboardContent content) async {
    final success = await MobileClipboardHelper.writeContent(content);
    if (!success) {
      _showSnackBar('接收失败');
    }
  }

  /// 搜索设备
  Future<void> _searchDevices() async {
    setState(() {
      _isSearching = true;
      _devices.clear();
      _selectedDevice = null;
    });

    await _discoveryService.sendDiscoveryBroadcast(
      syncPort: _receiveFromPc ? _syncPort : null,
    );

    await Future.delayed(const Duration(seconds: 3));

    setState(() {
      _isSearching = false;
    });

    if (_devices.isEmpty) {
      _showSnackBar('未发现设备');
    }
  }

  /// 发送内容
  Future<void> _sendContent() async {
    if (_selectedDevice == null) {
      _showSnackBar('请先选择目标设备');
      return;
    }

    final text = _textController.text;
    if (text.trim().isEmpty) {
      _showSnackBar('请输入要发送的内容');
      return;
    }
    final content = text.trimRight();

    String? passwordHash;
    if (_selectedDevice!.requiresPassword) {
      final deviceKey = '${_selectedDevice!.ip}:${_selectedDevice!.port}';
      passwordHash = _devicePasswords[deviceKey];

      if (passwordHash == null) {
        final password = await _showPasswordDialog();
        if (password == null) {
          return;
        }
        final salt = _selectedDevice!.salt ?? '';
        passwordHash = AuthService.hashPassword(password, salt);
        _devicePasswords[deviceKey] = passwordHash;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('overlay_password_hash', passwordHash);
        if (_encryptionEnabled) {
          _encryptionKey = await EncryptionService.deriveKey(passwordHash);
          _fileTransferService.setEncryption(enabled: _encryptionEnabled, key: _encryptionKey);
        }
      }
    }

    setState(() {
      _isSending = true;
    });

    _socketService.setEncryption(enabled: _encryptionEnabled, key: _encryptionKey);
    final result = await _socketService.sendMessage(
      _selectedDevice!.ip,
      _selectedDevice!.port,
      content,
      passwordHash: passwordHash,
    );

    setState(() {
      _isSending = false;
    });

    if (result.success) {
      _textController.clear();
    } else {
      if (_selectedDevice!.requiresPassword) {
        final deviceKey = '${_selectedDevice!.ip}:${_selectedDevice!.port}';
        _devicePasswords.remove(deviceKey);
      }
      _showSnackBar('发送失败: ${result.error ?? "请检查网络连接"}');
    }
  }

  /// 发送控制指令到电脑
  Future<void> _sendCommand(String command, String label, {bool silent = false}) async {
    if (_selectedDevice == null) {
      if (!silent) _showSnackBar('请先选择目标设备');
      return;
    }

    _cancelAutoSendTimer();

    String? passwordHash;
    if (_selectedDevice!.requiresPassword) {
      final deviceKey = '${_selectedDevice!.ip}:${_selectedDevice!.port}';
      passwordHash = _devicePasswords[deviceKey];
      if (passwordHash == null) {
        if (silent) return;
        final password = await _showPasswordDialog();
        if (password == null) return;
        final salt = _selectedDevice!.salt ?? '';
        passwordHash = AuthService.hashPassword(password, salt);
        _devicePasswords[deviceKey] = passwordHash;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('overlay_password_hash', passwordHash);
        if (_encryptionEnabled) {
          _encryptionKey = await EncryptionService.deriveKey(passwordHash);
          _fileTransferService.setEncryption(enabled: _encryptionEnabled, key: _encryptionKey);
        }
      }
    }

    _socketService.setEncryption(enabled: _encryptionEnabled, key: _encryptionKey);
    final result = await _socketService.sendMessage(
      _selectedDevice!.ip,
      _selectedDevice!.port,
      command,
      passwordHash: passwordHash,
    );

    if (!silent && !result.success) {
      _showSnackBar('发送失败');
    }
  }

  void _openTouchpad() {
    if (_selectedDevice == null) return;

    final deviceKey = '${_selectedDevice!.ip}:${_selectedDevice!.port}';
    final passwordHash = _devicePasswords[deviceKey];

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TouchpadScreen(
          device: _selectedDevice!,
          passwordHash: passwordHash,
        ),
      ),
    );
  }

  void _toggleRemoteScreen() {
    if (_selectedDevice == null) return;

    final deviceKey = '${_selectedDevice!.ip}:${_selectedDevice!.port}';
    final passwordHash = _devicePasswords[deviceKey];

    RemoteScreenOverlayManager.toggle(
      context,
      device: _selectedDevice!,
      passwordHash: passwordHash,
      encryptionKey: _encryptionKey,
      encryptionEnabled: _encryptionEnabled,
    );
    setState(() {}); // 刷新按钮状态
  }

  void _openSimpleInput() {
    if (_selectedDevice == null) return;

    final deviceKey = '${_selectedDevice!.ip}:${_selectedDevice!.port}';
    final passwordHash = _devicePasswords[deviceKey];

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SimpleInputScreen(
          device: _selectedDevice!,
          passwordHash: passwordHash,
        ),
      ),
    );
  }

  void _openAppGrid() async {
    if (_selectedDevice == null) return;

    String? passwordHash;
    if (_selectedDevice!.requiresPassword) {
      final deviceKey = '${_selectedDevice!.ip}:${_selectedDevice!.port}';
      passwordHash = _devicePasswords[deviceKey];
      if (passwordHash == null) {
        final password = await _showPasswordDialog();
        if (password == null) return;
        final salt = _selectedDevice!.salt ?? '';
        passwordHash = AuthService.hashPassword(password, salt);
        _devicePasswords[deviceKey] = passwordHash;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('overlay_password_hash', passwordHash);
        if (_encryptionEnabled) {
          _encryptionKey = await EncryptionService.deriveKey(passwordHash);
          _fileTransferService.setEncryption(enabled: _encryptionEnabled, key: _encryptionKey);
        }
      }
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AppGridScreen(
          device: _selectedDevice!,
          passwordHash: passwordHash,
        ),
      ),
    );
  }

  Future<void> _saveToMemory() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      _showSnackBar('请输入要暂存的内容');
      return;
    }

    await _textMemoryService.add(text);
    _textController.clear();
    await _loadMemoryCount();
  }

  Future<void> _saveDeviceForOverlay(Device? device) async {
    if (device == null) return;
    final prefs = await SharedPreferences.getInstance();
    final deviceJson = '{"ip":"${device.ip}","port":${device.port},"name":"${device.name}"}';
    await prefs.setString('overlay_selected_device', deviceJson);
  }

  void _openTextMemory() {
    if (_selectedDevice == null) return;

    final deviceKey = '${_selectedDevice!.ip}:${_selectedDevice!.port}';
    final passwordHash = _devicePasswords[deviceKey];

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TextMemoryScreen(
          device: _selectedDevice!,
          passwordHash: passwordHash,
        ),
      ),
    ).then((_) {
      _loadMemoryCount();
    });
  }

  Future<void> _toggleAutoSend() async {
    final newValue = !_autoSendEnabled;
    setState(() {
      _autoSendEnabled = newValue;
      if (!newValue) _cancelAutoSendTimer();
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoSendEnabledKey, newValue);
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          callbacks: SettingsCallbacks(
            onReceiveFromPcChanged: (value) {
              setState(() => _receiveFromPc = value);
              if (value) {
                _startSyncService();
              } else {
                _stopSyncService();
              }
            },
            onAutoSendChanged: (value) {
              setState(() {
                _autoSendEnabled = value;
                if (!value) _cancelAutoSendTimer();
              });
            },
            onAutoSendDelayChanged: (value) {
              setState(() => _autoSendDelay = value);
              _cancelAutoSendTimer();
            },
            onEncryptionChanged: (value) {
              setState(() => _encryptionEnabled = value);
              _clipboardSyncService.setEncryption(enabled: value, key: _encryptionKey);
              _fileTransferService.setEncryption(enabled: value, key: _encryptionKey);
            },
          ),
        ),
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  /// 打开扫码页面
  Future<void> _openQRScan() async {
    final result = await Navigator.push<Device>(
      context,
      MaterialPageRoute(builder: (context) => const QRScanScreen()),
    );

    if (result != null && mounted) {
      setState(() {
        // 检查设备是否已在列表中
        final exists = _devices.any((d) => d.ip == result.ip);
        if (!exists) {
          _devices.add(result);
        }
        _selectedDevice = result;
      });
      _showSnackBar('已连接到: ${result.name}');
    }
  }
}
