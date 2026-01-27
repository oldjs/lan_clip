import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../services/auth_service.dart';
import '../services/encryption_service.dart';
import '../services/overlay_service.dart';
import '../services/file_transfer_service.dart';
import '../main.dart' show startHiddenKey;
import '../widgets/settings/settings_tiles.dart';

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
  
  // 悬浮窗设置 (仅 Android)
  bool _overlayEnabled = false;
  
  // 文件传输设置
  String _downloadPath = '';
  int _cacheSize = 0;

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
    
    // 加载悬浮窗状态 (Android)
    if (Platform.isAndroid) {
      final overlayActive = await OverlayService.isActive();
      setState(() => _overlayEnabled = overlayActive);
    }
    
    // 加载文件传输设置
    await _loadFileTransferSettings();
  }
  
  /// 加载文件传输设置
  Future<void> _loadFileTransferSettings() async {
    final transferService = FileTransferService();
    final path = await transferService.getDownloadPath();
    final size = await transferService.getCacheSize();
    if (mounted) {
      setState(() {
        _downloadPath = path;
        _cacheSize = size;
      });
    }
  }
  
  /// 格式化文件大小
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
  
  /// 清理下载缓存
  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清理缓存'),
        content: Text('确定要清理下载缓存吗?\n\n将删除 ${_formatBytes(_cacheSize)} 的文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      final transferService = FileTransferService();
      await transferService.clearCache();
      await _loadFileTransferSettings();
      _showSnackBar('缓存已清理');
    }
  }

  /// 选择下载目录 (仅桌面端)
  Future<void> _pickDownloadPath() async {
    if (Platform.isAndroid || Platform.isIOS) return;
    
    final String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择保存位置',
      initialDirectory: _downloadPath,
    );

    if (selectedDirectory != null) {
      final transferService = FileTransferService();
      await transferService.setDownloadPath(selectedDirectory);
      await _loadFileTransferSettings();
    }
  }

  /// 打开下载目录
  Future<void> _openDownloadFolder() async {
    if (_downloadPath.isEmpty) return;
    
    final dir = Directory(_downloadPath);
    if (await dir.exists()) {
      await OpenFilex.open(_downloadPath);
    } else {
      _showSnackBar('目录不存在');
    }
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
  
  /// 设置悬浮窗开关
  Future<void> _setOverlayEnabled(bool value) async {
    if (!Platform.isAndroid) return;
    
    if (value) {
      // 检查权限
      final hasPermission = await OverlayService.checkPermission();
      if (!hasPermission) {
        // 显示权限说明对话框
        final shouldRequest = await _showOverlayPermissionDialog();
        if (shouldRequest == true) {
          await OverlayService.requestPermission();
          // 用户从设置返回后再次检查
          await Future.delayed(const Duration(milliseconds: 500));
          final granted = await OverlayService.checkPermission();
          if (!granted) {
            _showSnackBar('请在系统设置中允许悬浮窗权限');
            return;
          }
        } else {
          return;
        }
      }
      // 显示悬浮窗
      await OverlayService.showOverlay();
      setState(() => _overlayEnabled = true);
    } else {
      // 关闭悬浮窗
      await OverlayService.closeOverlay();
      setState(() => _overlayEnabled = false);
    }
  }
  
  /// 显示悬浮窗权限说明对话框
  Future<bool?> _showOverlayPermissionDialog() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('悬浮窗权限'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('开启悬浮窗功能需要以下权限：'),
            SizedBox(height: 12),
            Text('- 显示在其他应用上层', style: TextStyle(fontSize: 14)),
            SizedBox(height: 8),
            Text(
              '此权限用于在您使用其他应用（如游戏）时，显示快捷发送窗口。',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('去设置'),
          ),
        ],
      ),
    );
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
                 const SettingsSectionHeader(title: '剪贴板'),
                 Card(
                   child: Column(
                     children: [
                       // 桌面端设置
                       if (isDesktop) ...[
                        SettingsSwitchTile(
                          title: '自动粘贴',
                          subtitle: '收到内容后自动在光标位置粘贴',
                          icon: PhosphorIconsRegular.clipboardText,
                          value: _autoPaste,
                          onChanged: _setAutoPaste,
                        ),
                        const Divider(height: 1),
                        SettingsSwitchTile(
                          title: '同步到手机',
                          subtitle: '复制内容自动同步到已连接的手机',
                          icon: PhosphorIconsRegular.linkSimple,
                          value: _syncToMobile,
                          onChanged: _setSyncToMobile,
                        ),
                      ],
                      // 手机端设置
                      if (!isDesktop) ...[
                        SettingsSwitchTile(
                          title: '接收PC剪贴板',
                          subtitle: '允许电脑推送剪贴板内容到手机',
                          icon: PhosphorIconsRegular.downloadSimple,
                          value: _receiveFromPc,
                          onChanged: _setReceiveFromPc,
                        ),
                        const Divider(height: 1),
                        SettingsSwitchTile(
                          title: '自动发送',
                          subtitle: '停止输入后自动发送到电脑',
                          icon: PhosphorIconsRegular.uploadSimple,
                          value: _autoSendEnabled,
                          onChanged: _setAutoSendEnabled,
                        ),
                        if (_autoSendEnabled) ...[
                          const Divider(height: 1),
                          SettingsSliderTile(
                            title: '发送延迟',
                            icon: PhosphorIconsRegular.clockCounterClockwise,
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
                   const SettingsSectionHeader(title: '触摸板'),
                   Card(
                     child: SettingsSliderTile(
                       title: '灵敏度',
                       icon: PhosphorIconsRegular.handTap,
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
                   
                   // 悬浮窗设置组（仅 Android）
                   if (Platform.isAndroid) ...[
                     const SettingsSectionHeader(title: '悬浮窗'),
                     Card(
                       child: SettingsSwitchTile(
                         title: '启用悬浮窗',
                         subtitle: _overlayEnabled ? '游戏时可快捷发送内容' : '开启后可在其他应用上显示快捷窗口',
                         icon: PhosphorIconsRegular.appWindow,
                         value: _overlayEnabled,
                         onChanged: _setOverlayEnabled,
                       ),
                     ),
                     const SizedBox(height: 16),
                   ],
                 ],

                // 安全设置组
                 const SettingsSectionHeader(title: '安全'),
                 Card(
                   child: Column(
                     children: [
                      SettingsSwitchTile(
                        title: '密码保护',
                        subtitle: _passwordEnabled ? '已启用，连接需要密码' : '未启用，任何人都可连接',
                        icon: PhosphorIconsRegular.lockSimple,
                        value: _passwordEnabled,
                        onChanged: _setPasswordEnabled,
                      ),
                      if (_passwordEnabled) ...[
                        const Divider(height: 1),
                        ListTile(
                          leading: PhosphorIcon(
                            PhosphorIconsRegular.key,
                            size: 20,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          title: const Text('修改密码'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _changePassword,
                        ),
                      ],
                      const Divider(height: 1),
                      SettingsSwitchTile(
                        title: '加密传输',
                        subtitle: _encryptionEnabled ? '已启用端到端加密' : '数据以明文传输',
                        icon: PhosphorIconsRegular.shieldCheck,
                        value: _encryptionEnabled,
                        onChanged: _setEncryptionEnabled,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 文件传输设置组
                const SettingsSectionHeader(title: '文件传输'),
                Card(
                  child: Column(
                    children: [
                      // 下载目录
                      ListTile(
                        leading: PhosphorIcon(
                          PhosphorIconsRegular.folderOpen,
                          size: 20,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        title: const Text('下载目录'),
                        subtitle: Text(
                          _downloadPath,
                          style: const TextStyle(fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 桌面端显示编辑按钮
                            if (!Platform.isAndroid && !Platform.isIOS)
                              IconButton(
                                icon: PhosphorIcon(
                                  PhosphorIconsRegular.pencilSimple,
                                  size: 18,
                                ),
                                tooltip: '修改',
                                onPressed: _pickDownloadPath,
                              ),
                            IconButton(
                              icon: PhosphorIcon(
                                PhosphorIconsRegular.arrowSquareOut,
                                size: 18,
                              ),
                              tooltip: '打开',
                              onPressed: _openDownloadFolder,
                            ),
                          ],
                        ),
                        onTap: _openDownloadFolder,
                      ),
                      const Divider(height: 1),
                      // 缓存大小和清理
                      ListTile(
                        leading: PhosphorIcon(
                          PhosphorIconsRegular.trashSimple,
                          size: 20,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        title: const Text('清理缓存'),
                        subtitle: Text(
                          '已用空间: ${_formatBytes(_cacheSize)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: TextButton(
                          onPressed: _cacheSize > 0 ? _clearCache : null,
                          child: const Text('清理'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 启动设置组（仅桌面端）
                if (isDesktop) ...[
                  const SettingsSectionHeader(title: '启动'),
                  Card(
                    child: Column(
                      children: [
                        SettingsSwitchTile(
                          title: '开机自启',
                          subtitle: '开机后自动启动程序',
                          icon: PhosphorIconsRegular.power,
                          value: _launchAtStartup,
                          onChanged: _setLaunchAtStartup,
                        ),
                        const Divider(height: 1),
                        SettingsSwitchTile(
                          title: '启动时隐藏',
                          subtitle: '启动后自动最小化到系统托盘',
                          icon: PhosphorIconsRegular.eyeSlash,
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
}
