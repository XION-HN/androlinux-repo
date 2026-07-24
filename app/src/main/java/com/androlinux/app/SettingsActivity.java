package com.androlinux.app;

import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.widget.Button;
import android.widget.TextView;
import android.widget.Toast;

public class SettingsActivity extends Activity {

    private final Handler mHandler = new Handler(Looper.getMainLooper());
    private TextView mDeviceInfo;
    private TextView mExecOutput;
    private final StringBuilder mDiagLog = new StringBuilder();   // 累积各次自检结果，供一键复制

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_settings);

        mDeviceInfo = findViewById(R.id.device_info);
        mExecOutput = findViewById(R.id.exec_test_output);
        TextView adbCmd = findViewById(R.id.adb_command);
        adbCmd.setText(Diagnostics.ADB_DISABLE_PHANTOM);

        mDeviceInfo.setText(Diagnostics.collectBasic(this));

        Button btnExec = findViewById(R.id.btn_exec_test);
        btnExec.setOnClickListener(v -> runTest("exec 自检", Diagnostics::execSelfTest));

        Button btnPython = findViewById(R.id.btn_python_test);
        btnPython.setOnClickListener(v -> runTest("Python 自检", Diagnostics::pythonSelfTest));

        Button btnPip = findViewById(R.id.btn_pip_test);
        btnPip.setOnClickListener(v -> runTest("pip 自检", Diagnostics::pipSelfTest));

        Button btnPhantom = findViewById(R.id.btn_phantom_test);
        btnPhantom.setOnClickListener(v -> runInBackground(
            Diagnostics::startPhantomStress,
            r -> Toast.makeText(this,
                "STRESS_STARTED".equals(r) ? "压测已启动，5 分钟后到终端执行 ps -A | grep -c sleep"
                                           : "压测异常: " + r,
                Toast.LENGTH_LONG).show()));

        Button btnCopyAdb = findViewById(R.id.btn_copy_adb);
        btnCopyAdb.setOnClickListener(v -> copyToClipboard("adb", Diagnostics.ADB_DISABLE_PHANTOM));

        Button btnCopyDiag = findViewById(R.id.btn_copy_diag);
        btnCopyDiag.setOnClickListener(v -> {
            String all = Diagnostics.collectBasic(this) + "\n" + mDiagLog.toString();
            copyToClipboard("diagnostics", all);
        });
    }

    /** 通用自检运行器：后台执行，结果累积进 mDiagLog（供复制），最新结果显示在输出区。 */
    private void runTest(String title, Task task) {
        mExecOutput.setVisibility(View.VISIBLE);
        mExecOutput.setText(title + " 运行中…");
        runInBackground(task, result -> {
            String entry = "--- " + title + " ---\n" + (result.isEmpty() ? "(无输出)" : result);
            mDiagLog.append(entry).append("\n\n");
            mExecOutput.setText(result.isEmpty() ? "(无输出)" : result);
        });
    }

    private interface Task { String run(); }
    private interface Done { void onDone(String result); }

    private void runInBackground(Task task, Done done) {
        new Thread(() -> {
            String r = task.run();
            mHandler.post(() -> done.onDone(r));
        }, "diag-task").start();
    }

    private void copyToClipboard(String label, String text) {
        ClipboardManager cm = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
        cm.setPrimaryClip(ClipData.newPlainText(label, text));
        Toast.makeText(this, "已复制", Toast.LENGTH_SHORT).show();
    }
}
