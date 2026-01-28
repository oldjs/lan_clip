# 项目级经验

- 请求-响应协议使用 `LC_REQ:` / `LC_RES:` 前缀封装 JSON，并与加密流程共用同一路径，不能按普通消息处理。
- 电脑端应用控制与进程激活依赖 PowerShell：启动用 `Start-Process`，进程列表与激活分别用 `Get-Process` 与 `WScript.Shell.AppActivate`。
- 手机端入口调整需同步拆分文件：`lib/screens/mobile_screen.dart` 与 `lib/screens/mobile_screen_actions.dart`、`lib/screens/mobile_screen_dialogs.dart`、`lib/screens/mobile_screen_ui.dart`。
- 电脑控制手机类指令走手机 `syncPort` 的剪贴板同步通道（`SocketService.pushCommandToDevices`），手机端需在 `ClipboardSyncService` 先分流 `CMD:` 再处理剪贴板内容。
- Android 锁屏需设备管理员接收器与策略 XML（`AndroidManifest.xml` + `res/xml/device_admin_receiver.xml`），并在手机设置默认关闭后手动授权。
