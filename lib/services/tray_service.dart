import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// 系统托盘服务 (仅 Windows)
class TrayService with TrayListener {
  static final TrayService _instance = TrayService._internal();
  factory TrayService() => _instance;
  TrayService._internal();

  bool _isInitialized = false;
  VoidCallback? onShowWindow;
  VoidCallback? onExitApp;

  /// 初始化托盘
  Future<void> init() async {
    if (_isInitialized || !Platform.isWindows) return;

    await trayManager.setIcon('assets/tray_icon.ico');
    
    // 设置托盘菜单
    final menu = Menu(
      items: [
        MenuItem(key: 'show', label: '显示窗口'),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: '退出'),
      ],
    );
    await trayManager.setContextMenu(menu);
    
    trayManager.addListener(this);
    _isInitialized = true;
  }

  /// 更新托盘提示文字
  Future<void> setToolTip(String tip) async {
    if (!Platform.isWindows) return;
    await trayManager.setToolTip(tip);
  }

  @override
  void onTrayIconMouseDown() {
    // 左键点击显示窗口
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    // 右键显示菜单
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        windowManager.show();
        windowManager.focus();
        onShowWindow?.call();
        break;
      case 'exit':
        onExitApp?.call();
        break;
    }
  }

  void dispose() {
    if (_isInitialized) {
      trayManager.removeListener(this);
    }
  }
}
