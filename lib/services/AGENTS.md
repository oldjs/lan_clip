# Services 经验

- `file_transfer_service.dart` 和 `socket_service.dart` 的 `setEncryption` 方法必须校验：`enabled && key == null` 时应自动设为 `enabled = false`，防止发送端加密而接收端无密钥导致解密失败。
- 加密密钥派生路径：`AuthService.hashPassword()` → `EncryptionService.deriveKey(hash)` → 传给 `setEncryption()`，两端必须使用相同的 hash 作为派生输入。
