package com.example.lan_clip

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.inputmethod.InputMethodManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // 与 Dart 端通信的 Channel 名称
    private val INPUT_CHANNEL = "com.example.lan_clip/input_method"
    private val ADMIN_CHANNEL = "com.example.lan_clip/device_admin"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 输入法选择器
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INPUT_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "showInputMethodPicker" -> {
                    showInputMethodPicker()
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // 设备管理员设置
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ADMIN_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openDeviceAdminSettings" -> {
                    openDeviceAdminSettings()
                    result.success(true)
                }
                "requestDeviceAdmin" -> {
                    requestDeviceAdmin()
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    // 显示系统输入法选择器
    private fun showInputMethodPicker() {
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        imm.showInputMethodPicker()
    }

    // 打开设备管理员设置页面
    private fun openDeviceAdminSettings() {
        try {
            // 尝试打开设备管理员列表页面
            val intent = Intent().apply {
                action = "android.settings.SECURITY_SETTINGS"
            }
            startActivity(intent)
        } catch (e: Exception) {
            // 如果失败，尝试打开设置主页
            try {
                val intent = Intent(android.provider.Settings.ACTION_SETTINGS)
                startActivity(intent)
            } catch (_: Exception) {}
        }
    }

    // 请求激活设备管理员（直接跳转到激活页面）
    private fun requestDeviceAdmin() {
        try {
            val componentName = ComponentName(this, DeviceAdminReceiver::class.java)
            val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, componentName)
                putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION, "LAN Clip 需要此权限来远程锁定屏幕。\n\n请点击「激活」按钮授权。")
            }
            startActivity(intent)
        } catch (e: Exception) {
            // 如果失败，打开安全设置
            openDeviceAdminSettings()
        }
    }
}
