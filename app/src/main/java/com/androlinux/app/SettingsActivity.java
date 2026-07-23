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
    private String mLastExecResult = "";

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
        btnExec.setOnClickListener(v -> runExecTest());

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
            String all = Diagnostics.collectBasic(this)
                + "\n--- exec 自检 ---\n" + mLastExecResult;
            copyToClipboard("diagnostics", all);
        });
    }

    private void runExecTest() {
        mExecOutput.setVisibility(View.VISIBLE);
        mExecOutput.setText("运行中…");
        runInBackground(Diagnostics::execSelfTest, result -> {
            mLastExecResult = result;
            mExecOutput.setText(result);
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
