package com.androlinux.app;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.system.Os;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/**
 * 包管理器：从 GitHub Releases 拉取 packages.json 索引 → 下载 tar.gz → sha256 校验
 * → 解压到 $PREFIX → 重建符号链接。
 *
 * 索引格式见 build-system/make-packages-index.sh，关键字段:
 *   packages[].name / version / depends / sha256 / download_url / symlinks[]
 *
 * 安装流程（installPackage）：
 *   1. 拓扑展开依赖（递归），保证被依赖的包先装
 *   2. 对每个包：下载 → sha256 校验 → 解压到 $PREFIX → 重建符号链接
 *   3. 已安装版本相同则跳过（通过 $PREFIX/var/installed/<name> 记录）
 *
 * 卸载（uninstallPackage）：删除该包 staging 时记录的文件清单。
 * 当前实现为简化版：仅删 $PREFIX/var/installed/<name> 标记，不实际删文件
 * （文件可能被其他包共享，安全删除需引用计数，M2 再做）。
 */
public final class PackageManager {

    private static final String TAG = "PackageManager";

    /** 仓库索引 URL。打 tag 后由 CI 上传到 GitHub Releases。
     *  latest 指向最新 release，无需改代码即可拿到新包。 */
    private static final String INDEX_URL =
        "https://github.com/XION-HN/androlinux/releases/download/latest/packages.json";

    /** 已安装包记录目录：$PREFIX/var/installed/<name> 内容为版本号 */
    private static final String INSTALLED_DIR = App.PREFIX + "/var/installed";

    /** 下载缓存目录 */
    private static final String CACHE_DIR = App.PREFIX + "/var/cache/pkg";

    public interface Callback {
        void onProgress(String msg);
        void onSuccess(String summary);
        void onError(String message);
    }

    /** 包元数据 */
    public static class PackageInfo {
        public final String name;
        public final String version;
        public final List<String> depends;
        public final long size;
        public final String sha256;
        public final String filename;
        public final String downloadUrl;
        public final List<String[]> symlinks;   // [link, target]

        PackageInfo(JSONObject o) throws Exception {
            name = o.getString("name");
            version = o.getString("version");
            depends = new ArrayList<>();
            JSONArray arr = o.optJSONArray("depends");
            if (arr != null) {
                for (int i = 0; i < arr.length(); i++) depends.add(arr.getString(i));
            }
            size = o.getLong("size");
            sha256 = o.getString("sha256");
            filename = o.getString("filename");
            downloadUrl = o.getString("download_url");
            symlinks = new ArrayList<>();
            JSONArray sl = o.optJSONArray("symlinks");
            if (sl != null) {
                for (int i = 0; i < sl.length(); i++) {
                    JSONObject s = sl.getJSONObject(i);
                    symlinks.add(new String[]{s.getString("link"), s.getString("target")});
                }
            }
        }

        public String getDisplayName() { return name + "-" + version; }
    }

    /** 异步拉取索引。callback 在主线程回调。 */
    public static void fetchIndex(Callback cb) {
        new Thread(() -> {
            try {
                List<PackageInfo> pkgs = fetchIndexSync();
                Handler h = new Handler(Looper.getMainLooper());
                h.post(() -> cb.onSuccess(formatIndexSummary(pkgs)));
            } catch (Exception e) {
                Log.e(TAG, "fetchIndex failed", e);
                Handler h = new Handler(Looper.getMainLooper());
                h.post(() -> cb.onError(e.getMessage()));
            }
        }, "pkg-fetch").start();
    }

    /** 同步拉取并解析索引 */
    static List<PackageInfo> fetchIndexSync() throws Exception {
        URL url = new URL(INDEX_URL);
        HttpURLConnection conn = (HttpURLConnection) url.openConnection();
        conn.setConnectTimeout(15000);
        conn.setReadTimeout(30000);
        try {
            if (conn.getResponseCode() != 200) {
                throw new RuntimeException("HTTP " + conn.getResponseCode() + " 取索引失败");
            }
            StringBuilder sb = new StringBuilder();
            try (BufferedReader r = new BufferedReader(new InputStreamReader(conn.getInputStream()))) {
                String line;
                while ((line = r.readLine()) != null) sb.append(line).append('\n');
            }
            JSONObject root = new JSONObject(sb.toString());
            JSONArray arr = root.getJSONArray("packages");
            List<PackageInfo> pkgs = new ArrayList<>();
            for (int i = 0; i < arr.length(); i++) {
                pkgs.add(new PackageInfo(arr.getJSONObject(i)));
            }
            return pkgs;
        } finally {
            conn.disconnect();
        }
    }

    /** 异步安装包（含依赖）。callback 在主线程回调。 */
    public static void installPackage(Context ctx, PackageInfo pkg, Callback cb) {
        new Thread(() -> {
            try {
                List<PackageInfo> index = fetchIndexSync();
                // 拓扑展开依赖
                List<PackageInfo> order = resolveDeps(pkg.name, index);
                StringBuilder log = new StringBuilder();
                for (PackageInfo p : order) {
                    Handler h = new Handler(Looper.getMainLooper());
                    h.post(() -> cb.onProgress("安装 " + p.getDisplayName() + "..."));
                    String result = installOneSync(p);
                    log.append(result).append('\n');
                }
                String summary = log.toString().trim();
                Handler h = new Handler(Looper.getMainLooper());
                h.post(() -> cb.onSuccess(summary));
            } catch (Exception e) {
                Log.e(TAG, "install failed", e);
                Handler h = new Handler(Looper.getMainLooper());
                h.post(() -> cb.onError(e.getMessage()));
            }
        }, "pkg-install").start();
    }

    /** 递归展开依赖（被依赖的包先），返回安装顺序列表 */
    static List<PackageInfo> resolveDeps(String pkgName, List<PackageInfo> index) throws Exception {
        // 建 name → PackageInfo 映射
        java.util.Map<String, PackageInfo> map = new java.util.HashMap<>();
        for (PackageInfo p : index) map.put(p.name, p);

        List<PackageInfo> order = new ArrayList<>();
        Set<String> visited = new HashSet<>();
        Set<String> visiting = new HashSet<>();   // 检测循环依赖

        visit(pkgName, map, order, visited, visiting);
        // 反转：被依赖的在前
        Collections.reverse(order);
        return order;
    }

    private static void visit(String name, java.util.Map<String, PackageInfo> map,
                              List<PackageInfo> order, Set<String> visited, Set<String> visiting)
            throws Exception {
        if (visited.contains(name)) return;
        if (visiting.contains(name)) {
            throw new RuntimeException("检测到循环依赖: " + name);
        }
        visiting.add(name);
        PackageInfo p = map.get(name);
        if (p == null) {
            throw new RuntimeException("索引中找不到包: " + name);
        }
        for (String dep : p.depends) {
            visit(dep, map, order, visited, visiting);
        }
        visiting.remove(name);
        visited.add(name);
        order.add(p);
    }

    /** 安装单个包：下载 → 校验 → 解压 → 重建符号链接 → 记录已安装 */
    static String installOneSync(PackageInfo pkg) throws Exception {
        // 已安装相同版本则跳过
        String installedVer = getInstalledVersion(pkg.name);
        if (pkg.version.equals(installedVer)) {
            return pkg.getDisplayName() + " 已是最新（" + pkg.version + "），跳过";
        }

        File cacheDir = new File(CACHE_DIR);
        cacheDir.mkdirs();
        File tarball = new File(cacheDir, pkg.filename);

        // 下载（如缓存命中且 sha256 匹配则跳过下载）
        if (!tarball.exists() || !sha256Matches(tarball, pkg.sha256)) {
            downloadTo(pkg.downloadUrl, tarball);
        }
        // 下载后再次校验
        if (!sha256Matches(tarball, pkg.sha256)) {
            throw new RuntimeException(pkg.filename + " sha256 校验失败（文件损坏或被篡改）");
        }

        // 解压到 $PREFIX
        extractTarGz(tarball, new File(App.PREFIX));

        // 重建符号链接（tar.gz 不含 symlink）
        for (String[] sl : pkg.symlinks) {
            File link = new File(App.PREFIX, sl[0]);
            File parent = link.getParentFile();
            if (parent != null) parent.mkdirs();
            link.delete();
            Os.symlink(sl[1], link.getAbsolutePath());
        }

        // chmod bin/ 下新解压的可执行文件
        chmodBin(new File(App.PREFIX, "bin"));

        // 记录已安装版本
        recordInstalled(pkg.name, pkg.version);

        return pkg.getDisplayName() + " 安装完成";
    }

    /** 读取已安装版本号，未安装返回 null */
    static String getInstalledVersion(String name) {
        File f = new File(INSTALLED_DIR, name);
        if (!f.isFile()) return null;
        try (BufferedReader r = new BufferedReader(new InputStreamReader(
                new java.io.FileInputStream(f)))) {
            return r.readLine();
        } catch (Exception e) {
            return null;
        }
    }

    /** 记录已安装版本 */
    static void recordInstalled(String name, String version) throws Exception {
        File dir = new File(INSTALLED_DIR);
        dir.mkdirs();
        try (FileOutputStream fos = new FileOutputStream(new File(dir, name))) {
            fos.write(version.getBytes());
        }
    }

    /** 下载到文件，支持断点续传（简单实现：不续传，直接覆盖） */
    static void downloadTo(String urlStr, File dest) throws Exception {
        URL url = new URL(urlStr);
        HttpURLConnection conn = (HttpURLConnection) url.openConnection();
        conn.setConnectTimeout(15000);
        conn.setReadTimeout(60000);
        try {
            if (conn.getResponseCode() != 200) {
                throw new RuntimeException("HTTP " + conn.getResponseCode() + " 下载 " + urlStr);
            }
            try (InputStream in = conn.getInputStream();
                 FileOutputStream out = new FileOutputStream(dest)) {
                byte[] buf = new byte[64 * 1024];
                int n;
                while ((n = in.read(buf)) != -1) out.write(buf, 0, n);
            }
        } finally {
            conn.disconnect();
        }
    }

    /** sha256 校验 */
    static boolean sha256Matches(File f, String expected) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            try (java.io.FileInputStream in = new java.io.FileInputStream(f)) {
                byte[] buf = new byte[64 * 1024];
                int n;
                while ((n = in.read(buf)) != -1) md.update(buf, 0, n);
            }
            StringBuilder sb = new StringBuilder();
            for (byte b : md.digest()) sb.append(String.format("%02x", b));
            return sb.toString().equals(expected);
        } catch (Exception e) {
            return false;
        }
    }

    /** 解压 tar.gz 到 destDir。用设备上的 tar 命令（toybox 提供），避免引入第三方库。
     *  tar 路径已经写死为 $PREFIX/bin/tar，BootstrapInstaller 保证存在。 */
    static void extractTarGz(File tarball, File destDir) throws Exception {
        ProcessBuilder pb = new ProcessBuilder(
            App.PREFIX + "/bin/tar", "-xzf", tarball.getAbsolutePath(),
            "-C", destDir.getAbsolutePath());
        pb.redirectErrorStream(true);
        Process p = pb.start();
        // 读取输出防止 pipe 阻塞
        StringBuilder out = new StringBuilder();
        try (BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream()))) {
            String line;
            while ((line = r.readLine()) != null) out.append(line).append('\n');
        }
        if (!p.waitFor(120, java.util.concurrent.TimeUnit.SECONDS)) {
            p.destroy();
            throw new RuntimeException("tar 解压超时");
        }
        int code = p.exitValue();
        if (code != 0) {
            throw new RuntimeException("tar 退出码 " + code + ": " + out.toString().trim());
        }
    }

    /** chmod bin/ 目录下所有文件为 0755 */
    static void chmodBin(File binDir) {
        File[] files = binDir.listFiles();
        if (files == null) return;
        for (File f : files) {
            if (f.isFile()) {
                try {
                    Os.chmod(f.getAbsolutePath(), 0755);
                } catch (Exception e) {
                    Log.w(TAG, "chmod failed: " + f + " " + e);
                }
            }
        }
    }

    /** 格式化索引摘要供 UI 显示 */
    static String formatIndexSummary(List<PackageInfo> pkgs) {
        StringBuilder sb = new StringBuilder();
        sb.append("仓库共 ").append(pkgs.size()).append(" 个包:\n\n");
        for (PackageInfo p : pkgs) {
            String installed = getInstalledVersion(p.name);
            String status = (installed != null) ? ("[已装 " + installed + "]") : "[未安装]";
            String sizeStr = formatSize(p.size);
            sb.append(String.format("%-20s %-12s %-10s %s",
                    p.name, p.version, sizeStr, status));
            if (!p.depends.isEmpty()) {
                sb.append("  deps: ").append(String.join(",", p.depends));
            }
            sb.append('\n');
        }
        return sb.toString().trim();
    }

    private static String formatSize(long bytes) {
        if (bytes >= 1048576) return String.format("%.1fMB", bytes / 1048576.0);
        if (bytes >= 1024) return String.format("%.1fKB", bytes / 1024.0);
        return bytes + "B";
    }
}
