import 'dart:io';

class WindowsWindowService {
  /// 激活指定 PID 的主窗口
  static Future<bool> activateProcess(int pid) async {
    if (!Platform.isWindows) return false;
    if (pid <= 0) return false;

    // 使用 COM AppActivate 激活窗口
    final command =
        '\$wshell = New-Object -ComObject WScript.Shell; '
        'if (\$wshell.AppActivate($pid)) { exit 0 } else { exit 1 }';

    try {
      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-Command', command],
        runInShell: true,
      );
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
