package com.example.lan_clip

import android.content.Context
import android.view.inputmethod.InputMethodManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // 与 Dart 端通信的 Channel 名称
    private val CHANNEL = "com.example.lan_clip/input_method"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
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
    }

    // 显示系统输入法选择器
    private fun showInputMethodPicker() {
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        imm.showInputMethodPicker()
    }
}
