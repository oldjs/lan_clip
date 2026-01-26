import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import '../services/auth_service.dart';
import '../services/encryption_service.dart';
import '../main.dart' show startHiddenKey;

// SharedPreferences 键名
const String _autoPasteKey = 'auto_paste_enabled';
const String _syncToMobileKey = 'sync_to_mobile_enabled';
const String _autoSendEnabledKey = 'auto_send_enabled';
const String _autoSendDelayKey = 'auto_send_delay';
const String _receiveFromPcKey = 'receive_from_pc_enabled';
const String _touchpadSensitivityKey = 'touchpad_sensitivity';

/// 设置变更回调
class SettingsCallbacks {
  final Function(bool)? onAutoPasteChanged;
  final Function(bool)? onSyncToMobileChanged;
  final Function(bool)? onReceiveFromPcChanged;
  final Function(bool)? onAutoSendChanged;
  final Function(double)? onAutoSendDelayChanged;
  final Function(bool)? onPasswordChanged;
  final Function(bool)? onEncryptionChanged;
  final Function(bool)? onLaunchAtStartupChanged;
  final Function(bool)? onStartHiddenChanged;

  const SettingsCallbacks({
    this.onAutoPasteChanged,
    this.onSyncToMobileChanged,
    this.onReceiveFromPcChanged,
    this.onAutoSendChanged,
    this.onAutoSendDelayChanged,
    this.onPasswordChanged,
    this.onEncryptionChanged,
    this.onLaunchAtStartupChanged,
    this.onStartHiddenChanged,
  });
}

/// 统一设置页面
class SettingsScreen extends StatefulWidget {
  final SettingsCallbacks? callbacks;

  const SettingsScreen({super.key, this.callbacks});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // 剪贴板设置
  bool _autoPaste = false;
  bool _syncToMobile = false;
  bool _receiveFromPc = false;
  bool _autoSendEnabled = false;
  double _autoSendDelay = 3.0;

  // 触摸板设置
  double _touchpadSensitivity = 1.5;

  // 安全设置
  bool _passwordEnabled = false;
  bool _encryptionEnabled = false;

  // 启动设置
  bool _launchAtStartup = false;
  bool _startHidden = false;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAllSettings();
  }

  /// 加载所有设置
  Future<void> _loadAllSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final passwordEnabled = await AuthService.isPasswordEnabled();
    final encryptionEnabled = await EncryptionService.isEncryptionEnabled();

    bool startupEnabled = false;
    if (Platform.isWindows) {
      try {
        startupEnabled = await launchAtStartup.isEnabled();
      } catch (_) {}
    }

    setState(() {
      // 剪贴板
      _autoPaste = prefs.getBool(_autoPasteKey) ?? false;
      _syncToMobile = prefs.getBool(_syncToMobileKey) ?? false;
      _receiveFromPc = prefs.getBool(_receiveFromPcKey) ?? false;
      _autoSendEnabled = prefs.getBool(_autoSendEnabledKey) ?? false;
      _autoSendDelay = prefs.getDouble(_autoSendDelayKey) ?? 3.0;

      // 触摸板
      _touchpadSensitivity = prefs.getDouble(_touchpadSensitivityKey) ?? 1.5;

      // 安全
      _passwordEnabled = passwordEnabled;
      _encryptionEnabled = encryptionEnabled;

      // 启动
      _launchAtStartup = startupEnabled;
      _startHidden = prefs.getBool(startHiddenKey) ?? false;

      _isLoading = false;
    });
  }

  // ============== 设置项修改方法 ==============

  Future<void> _setAutoPaste(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoPasteKey, value);
    setState(() => _autoPaste = value);
    widget.callbacks?.onAutoPasteChanged?.call(value);
  }

  Future<void> _setSyncToMobile(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_syncToMobileKey, value);
    setState(() => _syncToMobile = value);
    widget.callbacks?.onSyncToMobileChanged?.call(value);
  }

  Future<void> _setReceiveFromPc(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_receiveFromPcKey, value);
    setState(() => _receiveFromPc = value);
    widget.callbacks?.onReceiveFromPcChanged?.call(value);
  }

  Future<void> _setAutoSendEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoSendEnabledKey, value);
    setState(() => _autoSendEnabled = value);
    widget.callbacks?.onAutoSendChanged?.call(value);
  }

  Future<void> _setAutoSendDelay(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_autoSendDelayKey, value);
    setState(() => _autoSendDelay = value);
    widget.callbacks?.onAutoSendDelayChanged?.call(value);
  }

  Future<void> _setTouchpadSensitivity(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_touchpadSensitivityKey, value);
    setState(() => _touchpadSensitivity = value);
  }

  Future<void> _setPasswordEnabled(bool value) async {
    if (value) {
      final password = await _showSetPasswordDialog();
      if (password != null && password.isNotEmpty) {
        await AuthService.setPassword(password);
        setState(() => _passwordEnabled = true);
        widget.callbacks?.onPasswordChanged?.call(true);
      }
    } else {
      await AuthService.clearPassword();
      setState(() => _passwordEnabled = false);
      widget.callbacks?.onPasswordChanged?.call(false);
    }
  }

  Future<void> _setEncryptionEnabled(bool value) async {
    await EncryptionService.setEncryptionEnabled(value);
    setState(() => _encryptionEnabled = value);
    widget.callbacks?.onEncryptionChanged?.call(value);
  }

  Future<void> _setLaunchAtStartup(bool value) async {
    if (!Platform.isWindows) return;
    try {
      if (value) {
        await launchAtStartup.enable();
      } else {
        await launchAtStartup.disable();
      }
      setState(() => _launchAtStartup = value);
      widget.callbacks?.onLaunchAtStartupChanged?.call(value);
    } catch (e) {
      _showSnackBar('设置失败: $e');
    }
  }

  Future<void> _setStartHidden(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(startHiddenKey, value);
    setState(() => _startHidden = value);
    widget.callbacks?.onStartHiddenChanged?.call(value);
  }

  /// 显示设置密码对话框
  Future<String?> _showSetPasswordDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('设置连接密码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '设置后，手机连接时需要输入此密码',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '密码',
                border: OutlineInputBorder(),
                hintText: '请输入密码',
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final password = controller.text.trim();
              if (password.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('密码不能为空')),
                );
                return;
              }
              Navigator.pop(context, password);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 修改密码
  Future<void> _changePassword() async {
    final password = await _showSetPasswordDialog();
    if (password != null && password.isNotEmpty) {
      await AuthService.setPassword(password);
      _showSnackBar('密码已更新');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 剪贴板设置组
                _buildSectionHeader('剪贴板'),
                Card(
                  child: Column(
                    children: [
                      // 桌面端设置
                      if (isDesktop) ...[
                        _buildSwitchTile(
                          title: '自动粘贴',
                          subtitle: '收到内容后自动在光标位置粘贴',
                          value: _autoPaste,
                          onChanged: _setAutoPaste,
                        ),
                        const Divider(height: 1),
                        _buildSwitchTile(
                          title: '同步到手机',
                          subtitle: '复制内容自动同步到已连接的手机',
                          value: _syncToMobile,
                          onChanged: _setSyncToMobile,
                        ),
                      ],
                      // 手机端设置
                      if (!isDesktop) ...[
                        _buildSwitchTile(
                          title: '接收PC剪贴板',
                          subtitle: '允许电脑推送剪贴板内容到手机',
                          value: _receiveFromPc,
                          onChanged: _setReceiveFromPc,
                        ),
                        const Divider(height: 1),
                        _buildSwitchTile(
                          title: '自动发送',
                          subtitle: '停止输入后自动发送到电脑',
                          value: _autoSendEnabled,
                          onChanged: _setAutoSendEnabled,
                        ),
                        if (_autoSendEnabled) ...[
                          const Divider(height: 1),
                          _buildSliderTile(
                            title: '发送延迟',
                            value: _autoSendDelay,
                            min: 0.5,
                            max: 10.0,
                            divisions: 19,
                            suffix: '秒',
                            onChanged: (v) => setState(() => _autoSendDelay = v),
                            onChangeEnd: _setAutoSendDelay,
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 触摸板设置组（仅手机端）
                if (!isDesktop) ...[
                  _buildSectionHeader('触摸板'),
                  Card(
                    child: _buildSliderTile(
                      title: '灵敏度',
                      value: _touchpadSensitivity,
                      min: 0.5,
                      max: 3.0,
                      divisions: 25,
                      suffix: 'x',
                      onChanged: (v) => setState(() => _touchpadSensitivity = v),
                      onChangeEnd: _setTouchpadSensitivity,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // 安全设置组
                _buildSectionHeader('安全'),
                Card(
                  child: Column(
                    children: [
                      _buildSwitchTile(
                        title: '密码保护',
                        subtitle: _passwordEnabled ? '已启用，连接需要密码' : '未启用，任何人都可连接',
                        value: _passwordEnabled,
                        onChanged: _setPasswordEnabled,
                      ),
                      if (_passwordEnabled) ...[
                        const Divider(height: 1),
                        ListTile(
                          title: const Text('修改密码'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _changePassword,
                        ),
                      ],
                      const Divider(height: 1),
                      _buildSwitchTile(
                        title: '加密传输',
                        subtitle: _encryptionEnabled ? '已启用端到端加密' : '数据以明文传输',
                        value: _encryptionEnabled,
                        onChanged: _setEncryptionEnabled,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 启动设置组（仅桌面端）
                if (isDesktop) ...[
                  _buildSectionHeader('启动'),
                  Card(
                    child: Column(
                      children: [
                        _buildSwitchTile(
                          title: '开机自启',
                          subtitle: '开机后自动启动程序',
                          value: _launchAtStartup,
                          onChanged: _setLaunchAtStartup,
                        ),
                        const Divider(height: 1),
                        _buildSwitchTile(
                          title: '启动时隐藏',
                          subtitle: '启动后自动最小化到系统托盘',
                          value: _startHidden,
                          onChanged: _setStartHidden,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  /// 构建分组标题
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  /// 构建开关设置项
  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return SwitchListTile(
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
      value: value,
      onChanged: onChanged,
    );
  }

  /// 构建滑块设置项
  Widget _buildSliderTile({
    required String title,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String suffix,
    required Function(double) onChanged,
    required Function(double) onChangeEnd,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title),
              Text(
                '${value.toStringAsFixed(1)}$suffix',
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ],
      ),
    );
  }
}
