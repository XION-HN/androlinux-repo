# 设备验证清单（技术验证 demo）

> 每台设备约 30 分钟。安装包：CI Artifacts → `androlinux-apk` 中的 `app-debug.apk`（`adb install` 或拷贝安装，允许"未知来源"）。
> 记录表填在本文档下方，完成后形成《验证报告》。

## 设备矩阵

| # | 设备 | 系统 | Android 版本 | 场景1 | 场景2 | 场景3 | 备注 |
|---|---|---|---|---|---|---|---|
| 1 | Pixel / AOSP | | | | | | |
| 2 | 小米 | HyperOS | | | | | |
| 3 | 华为 | EMUI / HarmonyOS 4.x | | | | | |
| 4 | OPPO | ColorOS | | | | | |
| 5 | vivo | OriginOS | | | | | |

## 场景 1：安装启动

- [ ] 安装 APK 成功，首次启动出现"正在初始化 Linux 环境…"
- [ ] 初始化完成后进入终端，提示符为 `[u0_aXXX@androlinux ~]$` 形式
- [ ] 依次执行正常：`ls`、`ps`、`df`、`echo $PREFIX`
- 失败时：进入"诊断"页 → 复制全部诊断信息（含 SELinux 状态）

## 场景 2：动态链接（三层 .so 链）

- [ ] "诊断"页 → 「运行 exec 自检」输出含 `EXEC_OK` 与 `HTTP/1.1 200 OK`
- 或在终端手动执行：`curl -I https://www.baidu.com` 返回 200
- 失败时收集：`logcat \| grep -i avc`（SELinux denial）

## 场景 3：幻影进程压力

- [ ] "诊断"页 → 「幻影进程压测」提示已启动
- [ ] 等待 5 分钟，回终端执行：`ps -A | grep -c sleep`
  - 接近 40 → 该 ROM 未触发幻影杀手
  - 远小于 40 → 被清理，记录数值
- [ ] 电脑端执行 ADB 命令后复测一次：
  `adb shell "settings put global settings_enable_monitor_phantom_procs false"`

## 场景 4（P1-2）：手动装包演练

```bash
# 电脑端：从 CI 的 bootstrap-prod 产物取一个包
adb push bash-5.2.37-arm64-v8a.tar.gz /sdcard/Download/
# 手机终端内：
cd $PREFIX && tar -xzf /sdcard/Download/bash-5.2.37-arm64-v8a.tar.gz
bash --version   # 重装后仍可执行 → "下载→解压→执行"通路成立
```

## 验收判据（Go/No-Go）

- **P0-2**：≥4/5 设备场景 1+2 通过（失败须定位原因）
- **P1-1**：5 台设备幻影杀手行为均有结论
- **P1-2**：场景 4 通过
