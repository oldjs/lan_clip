import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// 存储权限服务
/// 处理 Android 存储权限请求
class StoragePermissionService {
  static const String _permissionAskedKey = 'storage_permission_asked';

  /// 检查是否需要请求权限
  static bool get needsPermission => Platform.isAndroid;

  /// 检查是否拥有权限
  static Future<bool> hasPermission() async {
    if (!Platform.isAndroid) return true;

    // Android 11+ (API 30+) 使用 MANAGE_EXTERNAL_STORAGE
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    if (androidInfo.version.sdkInt >= 30) {
      return await Permission.manageExternalStorage.isGranted;
    }

    // Android 10 及以下使用存储权限
    return await Permission.storage.isGranted;
  }

  /// 请求权限
  static Future<bool> requestPermission(BuildContext context) async {
    if (!Platform.isAndroid) return true;

    // 先检查是否已经有权限
    if (await hasPermission()) return true;

    // 显示说明对话框
    final shouldRequest = await showPermissionDialog(context);
    if (shouldRequest != true) return false;

    // 请求权限
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    PermissionStatus status;

    if (androidInfo.version.sdkInt >= 30) {
      status = await Permission.manageExternalStorage.request();
    } else {
      status = await Permission.storage.request();
    }

    if (status.isGranted) {
      await markPermissionAsked();
      return true;
    } else if (status.isPermanentlyDenied) {
      if (context.mounted) {
        showPermissionDeniedSnackBar(context);
      }
      return false;
    }
    
    return false;
  }

  /// 标记已请求过权限
  static Future<void> markPermissionAsked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_permissionAskedKey, true);
  }

  /// 显示权限说明对话框
  static Future<bool?> showPermissionDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.folder, color: Colors.blue),
            SizedBox(width: 8),
            Text('存储权限'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('文件传输功能需要以下权限:'),
            SizedBox(height: 12),
            _PermissionItem(
              icon: Icons.save_alt,
              text: '保存接收的文件',
            ),
            SizedBox(height: 8),
            _PermissionItem(
              icon: Icons.folder_open,
              text: '读取要发送的文件',
            ),
            SizedBox(height: 16),
            Text(
              '请在接下来的系统弹窗中点击"允许"。\n(Android 11+ 需要"所有文件访问权限")',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('稍后'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('授权'),
          ),
        ],
      ),
    );
  }

  /// 显示权限被拒绝的提示
  static void showPermissionDeniedSnackBar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('存储权限被拒绝，请在设置中手动开启'),
        action: SnackBarAction(
          label: '去设置',
          onPressed: () {
            openAppSettings();
          },
        ),
        duration: const Duration(seconds: 5),
      ),
    );
  }
}

/// 权限项组件
class _PermissionItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _PermissionItem({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontSize: 14)),
      ],
    );
  }
}
