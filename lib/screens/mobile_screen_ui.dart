part of 'mobile_screen.dart';

extension _MobileScreenStateUi on _MobileScreenState {
  Widget buildMobileScreen(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LAN Clip - 发送端'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (InputMethodService.isSupported)
            IconButton(
              icon: const Icon(Icons.keyboard),
              tooltip: '切换输入法',
              onPressed: () => InputMethodService.showInputMethodPicker(),
            ),
          IconButton(
            icon: const Icon(Icons.power_settings_new),
            tooltip: '电源控制',
            onPressed: _selectedDevice == null ? null : _showPowerMenu,
          ),
          IconButton(
            icon: const Icon(Icons.edit_note),
            tooltip: '简洁输入',
            onPressed: _selectedDevice == null ? null : _openSimpleInput,
          ),
          IconButton(
            icon: const Icon(Icons.touch_app),
            tooltip: '触摸板',
            onPressed: _selectedDevice == null ? null : _openTouchpad,
          ),
          IconButton(
            icon: Icon(
              Icons.desktop_windows,
              color: RemoteScreenOverlayManager.isShowing ? Colors.green : null,
            ),
            tooltip: '远程画面',
            onPressed: _selectedDevice == null ? null : _toggleRemoteScreen,
          ),
          IconButton(
            icon: const Icon(Icons.apps),
            tooltip: '应用控制',
            onPressed: _selectedDevice == null ? null : _openAppGrid,
          ),
          IconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.folder_shared),
                if (_activeTransferCount > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        '$_activeTransferCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            tooltip: '文件传输',
            onPressed: () {
              String? passwordHash;
              if (_selectedDevice != null && _selectedDevice!.requiresPassword) {
                final deviceKey = '${_selectedDevice!.ip}:${_selectedDevice!.port}';
                passwordHash = _devicePasswords[deviceKey];
              }

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => FileTransferScreen(
                    selectedDevice: _selectedDevice,
                    passwordHash: passwordHash,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('目标设备', style: TextStyle(fontSize: 16)),
                              Row(
                                children: [
                                  if (_selectedDevice != null)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: OutlinedButton(
                                        onPressed: () {
                                          setState(() => _selectedDevice = null);
                                          _showSnackBar('已断开连接');
                                        },
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.red,
                                        ),
                                        child: const Text('断开'),
                                      ),
                                    ),
                                  ElevatedButton.icon(
                                    onPressed: _isSearching ? null : _searchDevices,
                                    icon: _isSearching
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : const Icon(Icons.search),
                                    label: Text(_isSearching ? '搜索中' : '搜索'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.orange.shade200),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.info_outline, size: 16, color: Colors.orange),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '请先在电脑上打开 LAN Clip，再点击搜索',
                                    style: TextStyle(color: Colors.orange, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_devices.isEmpty)
                            const Text('点击搜索按钮发现局域网内的设备', style: TextStyle(color: Colors.grey))
                          else
                            DropdownButton<Device>(
                              isExpanded: true,
                              value: _selectedDevice,
                              hint: const Text('选择设备'),
                              items: _devices.map((device) {
                                return DropdownMenuItem<Device>(
                                  value: device,
                                  child: Text(device.toString()),
                                );
                              }).toList(),
                              onChanged: (device) {
                                setState(() => _selectedDevice = device);
                                _saveDeviceForOverlay(device);
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 150,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: TextField(
                          controller: _textController,
                          focusNode: _inputFocusNode,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          decoration: const InputDecoration(
                            hintText: '输入要发送到电脑剪切板的内容...',
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_countdownSeconds > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              value: _countdownSeconds / _autoSendDelay,
                              color: Colors.blue,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${_autoSendDelay.toStringAsFixed(1)}秒后发送($_countdownSeconds)...',
                            style: const TextStyle(color: Colors.blue),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _cancelAutoSendTimer,
                            child: const Text(
                              '取消',
                              style: TextStyle(
                                color: Colors.red,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_selectedDevice == null)
                        OutlinedButton.icon(
                          onPressed: _saveToMemory,
                          icon: const Icon(Icons.save_alt, size: 18),
                          label: Text(_memoryCount > 0 ? '暂存 ($_memoryCount)' : '暂存'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.orange,
                          ),
                        )
                      else
                        OutlinedButton.icon(
                          onPressed: _memoryCount > 0 ? _openTextMemory : _saveToMemory,
                          icon: Icon(
                            _memoryCount > 0 ? Icons.inventory_2_outlined : Icons.save_alt,
                            size: 18,
                          ),
                          label: Text(_memoryCount > 0 ? '记忆 ($_memoryCount)' : '暂存'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _memoryCount > 0 ? Colors.green : Colors.orange,
                          ),
                        ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: _toggleAutoSend,
                        icon: Icon(
                          _autoSendEnabled ? Icons.timer : Icons.timer_off_outlined,
                          size: 18,
                        ),
                        label: Text(_autoSendEnabled ? '自动' : '手动'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _autoSendEnabled ? Colors.blue : Colors.grey,
                          backgroundColor: _autoSendEnabled ? Colors.blue.withValues(alpha: 0.1) : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildCommandButtonWithLongPress(
                          icon: Icons.backspace_outlined,
                          label: '退格',
                          command: cmdBackspace,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildCommandButtonWithLongPress(
                          icon: Icons.space_bar,
                          label: '空格',
                          command: cmdSpace,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildCommandButtonWithLongPress(
                          icon: Icons.keyboard_return,
                          label: '回车',
                          command: cmdEnter,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildCommandButton(
                          icon: Icons.clear_all,
                          label: '清空',
                          command: cmdClear,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildArrowButton(Icons.keyboard_arrow_left, cmdArrowLeft, '左'),
                      const SizedBox(width: 4),
                      Column(
                        children: [
                          _buildArrowButton(Icons.keyboard_arrow_up, cmdArrowUp, '上'),
                          const SizedBox(height: 4),
                          _buildArrowButton(Icons.keyboard_arrow_down, cmdArrowDown, '下'),
                        ],
                      ),
                      const SizedBox(width: 4),
                      _buildArrowButton(Icons.keyboard_arrow_right, cmdArrowRight, '右'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: (_isSending || _selectedDevice == null) ? null : _sendContent,
                      icon: _isSending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                      label: Text(_isSending ? '发送中...' : '发送到电脑'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommandButton({
    required IconData icon,
    required String label,
    required String command,
    Color? color,
  }) {
    return OutlinedButton(
      onPressed: _selectedDevice == null ? null : () => _sendCommand(command, label),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildCommandButtonWithLongPress({
    required IconData icon,
    required String label,
    required String command,
    Color? color,
  }) {
    final isDisabled = _selectedDevice == null;

    return GestureDetector(
      onLongPressStart: isDisabled
          ? null
          : (_) {
              _sendCommand(command, label);
              _longPressTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
                _sendCommand(command, label, silent: true);
              });
            },
      onLongPressEnd: isDisabled
          ? null
          : (_) {
              _longPressTimer?.cancel();
              _longPressTimer = null;
            },
      child: OutlinedButton(
        onPressed: isDisabled ? null : () => _sendCommand(command, label),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildArrowButton(IconData icon, String command, String label) {
    final isDisabled = _selectedDevice == null;

    return SizedBox(
      width: 48,
      height: 48,
      child: GestureDetector(
        onLongPressStart: isDisabled
            ? null
            : (_) {
                _sendCommand(command, label, silent: true);
                _longPressTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
                  _sendCommand(command, label, silent: true);
                });
              },
        onLongPressEnd: isDisabled
            ? null
            : (_) {
                _longPressTimer?.cancel();
                _longPressTimer = null;
              },
        child: OutlinedButton(
          onPressed: isDisabled ? null : () => _sendCommand(command, label, silent: true),
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Icon(icon, size: 24),
        ),
      ),
    );
  }
}
