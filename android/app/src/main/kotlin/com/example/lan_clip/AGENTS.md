# Android Native 经验

- `device_policy_manager` 包的 `requestPermession()` 只显示提示，不会自动跳转。要直接跳转到激活页面，需用 MethodChannel 调用原生的 `DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN` Intent。
- 设备管理员激活 Intent 需要 `EXTRA_DEVICE_ADMIN`（ComponentName）和 `EXTRA_ADD_EXPLANATION`（说明文字），否则用户不知道为何要授权。
- 跳转系统设置的 fallback 顺序：`SECURITY_SETTINGS` → `ACTION_SETTINGS`，不同厂商 ROM 支持度不同。
