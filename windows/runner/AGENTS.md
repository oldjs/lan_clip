# Windows Runner 经验

- Flutter 3.38.x 存在严重帧率问题（issue #178916），临时解决方案是在 `main.cpp` 添加 `project.set_ui_thread_policy(flutter::UIThreadPolicy::RunOnSeparateThread);`，等 3.40 stable 发布后移除。
- 修改 `main.cpp` 时 LSP 会报假阳性错误（找不到 flutter 头文件），可以忽略；Flutter 构建系统会正确编译。
