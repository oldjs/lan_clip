import 'package:flutter/material.dart';
import 'overlay_widget.dart';

// 悬浮窗的独立入口点
// 使用 @pragma("vm:entry-point") 确保 AOT 编译时不会被移除
@pragma("vm:entry-point")
void overlayMain() {
  // 确保 Flutter 绑定初始化
  WidgetsFlutterBinding.ensureInitialized();
  
  // 启动悬浮窗应用
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      // 使用浅色主题
      themeMode: ThemeMode.light,
      home: OverlayWidget(),
    ),
  );
}
