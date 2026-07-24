package com.androlinux.app;

import android.content.Context;
import android.os.Build;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.InputStreamReader;
import java.util.concurrent.TimeUnit;

/** 设备矩阵验证的数据收集工具：信息聚合 / exec 自检 / 幻影压测 */
public final class Diagnostics {

    public static final String ADB_DISABLE_PHANTOM =
        "adb shell \"settings put global settings_enable_monitor_phantom_procs false\"";

    /** 基础设备信息（不含 exec 自检结果，自检耗时单独调用） */
    public static String collectBasic(Context ctx) {
        StringBuilder sb = new StringBuilder();
        sb.append("设备: ").append(Build.MANUFACTURER).append(' ').append(Build.MODEL).append('\n');
        sb.append("Android: ").append(Build.VERSION.RELEASE)
          .append(" (API ").append(Build.VERSION.SDK_INT).append(")\n");
        sb.append("fingerprint: ").append(Build.FINGERPRINT).append('\n');
        sb.append("SELinux: ").append(selinuxStatus()).append('\n');
        sb.append("app uid: ").append(android.os.Process.myUid()).append('\n');
        sb.append("bootstrap: ").append(BootstrapInstaller.isInstalled(ctx) ? "已安装" : "未安装").append('\n');
        sb.append("prefix: ").append(App.PREFIX).append('\n');
        return sb.toString();
    }

    /** exec 自检 = 设备矩阵场景 1+2 的半自动化 */
    public static String execSelfTest() {
        return runShell(bootstrapEnv(), App.PREFIX + "/bin/bash", "-c",
            "echo EXEC_OK; uname -m; ls $PREFIX/bin | wc -l; "
          + "curl -sI https://www.baidu.com | head -1");
    }

    /** Python 自检：验证解释器能启动并加载核心 C 扩展（覆盖多层 .so 依赖链） */
    public static String pythonSelfTest() {
        // import 列表刻意覆盖 _ssl/_hashlib/_ctypes/_sqlite3/_bz2/_lzma/pyexpat/readline
        // —— 任一缺失说明对应依赖 .so 在 lib/ 找不到或 RUNPATH 解析失败
        return runShell(bootstrapEnv(), App.PREFIX + "/bin/python3.13", "-c",
            "import sys,ssl,ctypes,sqlite3,bz2,lzma,hashlib,"
          + "xml.etree.ElementTree,readline;"
          + "print('PY_OK', sys.version.split()[0])");
    }

    /** pip 自检：验证 pip 入口脚本与 shebang、site-packages 安装完整 */
    public static String pipSelfTest() {
        return runShell(bootstrapEnv(), App.PREFIX + "/bin/pip3.13", "--version");
    }

    /** 幻影进程压测：fork 40 个 sleep 300（进程脱离父进程后由 init 收养，正是幻影杀手的目标） */
    public static String startPhantomStress() {
        return runShell(bootstrapEnv(), App.PREFIX + "/bin/bash", "-c",
            "for i in $(seq 1 40); do sleep 300 & done; echo STRESS_STARTED");
    }

    /** bootstrap 前缀环境变量（与 MainActivity.buildEnv 对齐，供 runShell 注入）。
     *  Runtime.exec 不继承终端会话 env，必须显式传入，否则子进程里 $PREFIX/$PATH 为空。 */
    private static String[] bootstrapEnv() {
        return new String[]{
            "TERM=xterm-256color",
            "HOME=" + App.HOME_PATH,
            "PREFIX=" + App.PREFIX,
            "PATH=" + App.PREFIX + "/bin",
            "TMPDIR=" + App.PREFIX + "/tmp",
            "LANG=C.UTF-8",
        };
    }

    private static String runShell(String... cmd) {
        return runShell(null, cmd);
    }

    private static String runShell(String[] envp, String... cmd) {
        StringBuilder out = new StringBuilder();
        try {
            Process p = Runtime.getRuntime().exec(cmd, envp, null);
            Thread t = new Thread(() -> {
                try (BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream()))) {
                    String line;
                    while ((line = r.readLine()) != null) out.append(line).append('\n');
                } catch (Exception ignored) { }
            });
            t.start();
            try (BufferedReader r = new BufferedReader(new InputStreamReader(p.getErrorStream()))) {
                String line;
                while ((line = r.readLine()) != null) out.append("[stderr] ").append(line).append('\n');
            }
            t.join();
            if (!p.waitFor(30, TimeUnit.SECONDS)) {
                p.destroy();
                out.append("[timeout]\n");
            }
        } catch (Exception e) {
            out.append("[exec失败] ").append(e.getMessage()).append('\n');
        }
        return out.toString().trim();
    }

    private static String selinuxStatus() {
        File f = new File("/sys/fs/selinux/enforce");
        if (!f.isFile()) return "unknown(no selinuxfs)";
        try (BufferedReader r = new BufferedReader(new FileReader(f))) {
            String s = r.readLine();
            return "1".equals(s) ? "enforcing" : "permissive";
        } catch (Exception e) {
            return "unknown(" + e.getMessage() + ")";
        }
    }
}
