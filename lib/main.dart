import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/mobile_screen.dart';
import 'screens/desktop_screen.dart';

// 是否为开机自启
bool isAutoStart = false;

// 启动时隐藏设置的存储键
const String startHiddenKey = 'start_hidden';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 检查是否为开机自启 (通过命令行参数)
  isAutoStart = args.contains('--autostart');
  
  // Windows 平台初始化
  if (Platform.isWindows) {
    // 初始化 launch_at_startup
    final packageInfo = await PackageInfo.fromPlatform();
    launchAtStartup.setup(
      appName: packageInfo.appName,
      appPath: Platform.resolvedExecutable,
      args: ['--autostart'],  // 自启时传递参数
    );
    
    // 读取用户设置：启动时是否隐藏到托盘
    final prefs = await SharedPreferences.getInstance();
    final startHidden = prefs.getBool(startHiddenKey) ?? false;
    
    // 窗口管理初始化
    await windowManager.ensureInitialized();
    
    const windowOptions = WindowOptions(
      size: Size(450, 600),
      minimumSize: Size(400, 500),
      center: true,
      title: 'LAN Clip',
      skipTaskbar: false,
    );
    
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      // 根据用户设置决定是否隐藏窗口
      if (startHidden) {
        await windowManager.hide();
      } else {
        await windowManager.show();
        await windowManager.focus();
      }
    });
  }
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LAN Clip',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: _buildHomeScreen(),
    );
  }

  /// 根据平台选择界面
  Widget _buildHomeScreen() {
    // Windows/macOS/Linux 作为接收端
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return const DesktopScreen();
    }
    // Android/iOS 作为发送端
    return const MobileScreen();
  }
}
