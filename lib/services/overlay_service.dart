import 'dart:io';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

/// 悬浮窗管理服务
class OverlayService {
  /// 检查悬浮窗权限
  static Future<bool> checkPermission() async {
    if (!Platform.isAndroid) return false;
    return await FlutterOverlayWindow.isPermissionGranted();
  }

  /// 请求悬浮窗权限(跳转系统设置)
  static Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return false;
    final bool? result = await FlutterOverlayWindow.requestPermission();
    return result ?? false;
  }

  /// 显示悬浮窗
  static Future<void> showOverlay() async {
    if (!Platform.isAndroid) return;
    
    // 检查权限
    if (!await checkPermission()) return;

    // 如果已经激活，先关闭
    if (await isActive()) {
      await closeOverlay();
    }

    await FlutterOverlayWindow.showOverlay(
      height: 56, // 小球初始高度
      width: 56,  // 小球初始宽度
      alignment: OverlayAlignment.centerRight,
      visibility: NotificationVisibility.visibilityPublic,
      flag: OverlayFlag.focusPointer,
      enableDrag: true,
      positionGravity: PositionGravity.right,
    );
  }

  /// 关闭悬浮窗
  static Future<void> closeOverlay() async {
    if (!Platform.isAndroid) return;
    await FlutterOverlayWindow.closeOverlay();
  }

  /// 检查悬浮窗是否显示中
  static Future<bool> isActive() async {
    if (!Platform.isAndroid) return false;
    return await FlutterOverlayWindow.isActive();
  }
}
