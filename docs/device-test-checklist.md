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

## 自动化辅助

### CI 状态自查（开发机侧）

私有仓库无法匿名访问，先用以下任一方式鉴权后运行 `scripts/ci-status.sh`：

```bash
# 方式 1：PAT（需勾选 repo + actions:read，创建于 https://github.com/settings/tokens）
export GH_TOKEN=ghp_xxx

# 方式 2：交互式登录（凭证持久化）
gh auth login

# 查最近 5 次 run + 最新 run 的 job/artifact（失败时自动 dump 末尾 80 行日志）
./scripts/ci-status.sh

# 仅看最新完成 run 的 artifact 下载信息
./scripts/ci-status.sh artifacts

# 查指定 run 的详情 + 失败日志
./scripts/ci-status.sh <run-id>

# 下载 APK artifact 到 ./dist/
gh run download <run-id> --repo XION-HN/androlinux --name androlinux-apk -D ./dist/
```

### 设备侧一键全量自检

App「诊断」页顶部「一键全量自检（exec+Python+pip）」按钮会按 spec 场景 1+2 顺序跑：
exec 自检 → Python 核心模块导入 → pip --version，输出结构化报告（含 PASS/FAIL 判定 + 汇总 X/3）。

报告会自动累积进「复制全部诊断信息」缓冲区，可直接粘贴到下方的验证报告汇总表。

> 幻影压测是异步长任务（fork 40×sleep 300，5 分钟后观测），单独按钮触发，不纳入一键序列。

## 验证报告汇总表

> 每台设备测完填写一行。一键自检报告粘贴到「自检报告」列（可折叠）。
> Go/No-Go 判据：P0-2 = 场景1+2 ≥4 台通过；P1-1 = 5 台幻影行为有结论；P1-2 = 场景4 通过。

| # | 设备 | 系统 | Android | 场景1+2 | 幻影存活数 | 场景4 | 结论 | 自检报告 |
|---|---|---|---|---|---|---|---|---|
| 1 | Pixel | AOSP | | PASS/FAIL | /40 | PASS/FAIL | Go/No-Go | <details><summary>展开</summary><pre>粘贴一键自检输出</pre></details> |
| 2 | 小米 | HyperOS | | | /40 | | | |
| 3 | 华为 | EMUI/HarmonyOS | | | /40 | | | |
| 4 | OPPO | ColorOS | | | /40 | | | |
| 5 | vivo | OriginOS | | | /40 | | | |

### 最终结论

- P0-2（场景 1+2 ≥4/5 通过）：[ ] 达标 / [ ] 未达标
- P1-1（幻影行为 5 台有结论）：[ ] 达标 / [ ] 未达标
- P1-2（场景 4 装包通路）：[ ] 达标 / [ ] 未达标

**整体 Go/No-Go**：[ ] Go（进入 Phase 2） / [ ] No-Go（列出阻塞项）
