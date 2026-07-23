package com.androlinux.app;

import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import android.util.Log;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.inputmethod.InputMethodManager;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import com.termux.terminal.TerminalSession;
import com.termux.terminal.TerminalSessionClient;
import com.termux.view.TerminalView;
import com.termux.view.TerminalViewClient;

public class MainActivity extends Activity {

    private static final String TAG = "MainActivity";
    private static final int TRANSCRIPT_ROWS = 2000;

    private TerminalView mTerminalView;
    private TerminalSession mSession;
    private LinearLayout mOverlay;
    private TextView mInstallStatus;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        mTerminalView = findViewById(R.id.terminal_view);
        mOverlay = findViewById(R.id.install_overlay);
        mInstallStatus = findViewById(R.id.install_status);
        Button btnSettings = findViewById(R.id.btn_settings);

        mTerminalView.setTerminalViewClient(mViewClient);
        mTerminalView.setKeepScreenOn(true);

        btnSettings.setOnClickListener(v ->
            startActivity(new Intent(this, SettingsActivity.class)));

        // 安装失败时点击重试
        mOverlay.setOnClickListener(v -> ensureBootstrap());

        ensureBootstrap();
    }

    private void ensureBootstrap() {
        if (BootstrapInstaller.isInstalled(this)) {
            startSession();
            return;
        }
        mOverlay.setVisibility(View.VISIBLE);
        mInstallStatus.setText(R.string.installing);
        BootstrapInstaller.installAsync(this, new BootstrapInstaller.Callback() {
            @Override public void onReady() {
                startSession();
            }
            @Override public void onError(String message) {
                mInstallStatus.setText(getString(R.string.install_failed) + "\n\n" + message);
            }
        });
    }

    private void startSession() {
        if (mSession != null && mSession.isRunning()) {
            mOverlay.setVisibility(View.GONE);
            return;
        }
        String shellPath = App.PREFIX + "/bin/bash";
        String[] env = buildEnv();
        mSession = new TerminalSession(shellPath, App.HOME_PATH, new String[]{}, env,
                TRANSCRIPT_ROWS, mSessionClient);
        mTerminalView.attachSession(mSession);
        mOverlay.setVisibility(View.GONE);
        mTerminalView.requestFocus();

        // 前台服务保活（会话期间持有部分唤醒锁由 TerminalView keepScreenOn 覆盖前台场景）
        startService(new Intent(this, TermService.class));
    }

    static String[] buildEnv() {
        return new String[]{
            "TERM=xterm-256color",
            "COLORTERM=truecolor",
            "HOME=" + App.HOME_PATH,
            "PREFIX=" + App.PREFIX,
            "PATH=" + App.PREFIX + "/bin",
            "TMPDIR=" + App.PREFIX + "/tmp",
            "LANG=C.UTF-8"
        };
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
    }

    // ------------------------------------------------------------------
    // TerminalSessionClient
    // ------------------------------------------------------------------
    private final TerminalSessionClient mSessionClient = new TerminalSessionClient() {
        @Override public void onTextChanged(TerminalSession changedSession) {
            mTerminalView.onScreenUpdated();
        }

        @Override public void onTitleChanged(TerminalSession changedSession) { }

        @Override public void onSessionFinished(TerminalSession finishedSession) {
            runOnUiThread(() -> {
                Toast.makeText(MainActivity.this, "会话已结束", Toast.LENGTH_SHORT).show();
                finish();
            });
        }

        @Override public void onCopyTextToClipboard(TerminalSession session, String text) {
            ClipboardManager cm = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
            cm.setPrimaryClip(ClipData.newPlainText("terminal", text));
        }

        @Override public void onPasteTextFromClipboard(TerminalSession session) {
            ClipboardManager cm = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
            ClipData clip = cm.getPrimaryClip();
            if (clip != null && clip.getItemCount() > 0) {
                CharSequence text = clip.getItemAt(0).getText();
                if (text != null && mSession != null && mSession.getEmulator() != null) {
                    mSession.getEmulator().paste(text.toString());
                }
            }
        }

        @Override public void onBell(TerminalSession session) { }

        @Override public void onColorsChanged(TerminalSession session) { }

        @Override public void onTerminalCursorStateChange(boolean state) { }

        @Override public void setTerminalShellPid(TerminalSession session, int pid) {
            Log.i(TAG, "shell pid=" + pid);
        }

        @Override public Integer getTerminalCursorStyle() {
            return null;
        }

        @Override public void logError(String tag, String message) { Log.e(tag, message); }
        @Override public void logWarn(String tag, String message) { Log.w(tag, message); }
        @Override public void logInfo(String tag, String message) { Log.i(tag, message); }
        @Override public void logDebug(String tag, String message) { Log.d(tag, message); }
        @Override public void logVerbose(String tag, String message) { Log.v(tag, message); }
        @Override public void logStackTraceWithMessage(String tag, String message, Exception e) {
            Log.e(tag, message, e);
        }
        @Override public void logStackTrace(String tag, Exception e) { Log.e(tag, "stacktrace", e); }
    };

    // ------------------------------------------------------------------
    // TerminalViewClient
    // ------------------------------------------------------------------
    private final TerminalViewClient mViewClient = new TerminalViewClient() {
        @Override public float onScale(float scale) {
            // 双指缩放字体，限制在 0.5x ~ 3x
            return Math.min(3.0f, Math.max(0.5f, scale));
        }

        @Override public void onSingleTapUp(MotionEvent e) {
            InputMethodManager imm = (InputMethodManager) getSystemService(Context.INPUT_METHOD_SERVICE);
            if (imm != null) imm.showSoftInput(mTerminalView, InputMethodManager.SHOW_IMPLICIT);
        }

        @Override public boolean shouldBackButtonBeMappedToEscape() { return false; }
        @Override public boolean shouldEnforceCharBasedInput() { return true; }
        @Override public boolean shouldUseCtrlSpaceWorkaround() { return false; }
        @Override public boolean isTerminalViewSelected() { return false; }
        @Override public void copyModeChanged(boolean copyMode) { }

        @Override public boolean onKeyDown(int keyCode, KeyEvent e, TerminalSession session) {
            return false;
        }

        @Override public boolean onKeyUp(int keyCode, KeyEvent e) { return false; }
        @Override public boolean onLongPress(MotionEvent event) { return false; }
        @Override public boolean readControlKey() { return false; }
        @Override public boolean readAltKey() { return false; }
        @Override public boolean readShiftKey() { return false; }
        @Override public boolean readFnKey() { return false; }

        @Override public boolean onCodePoint(int codePoint, boolean ctrlDown, TerminalSession session) {
            return false;
        }

        @Override public void onEmulatorSet() { }

        @Override public void logError(String tag, String message) { Log.e(tag, message); }
        @Override public void logWarn(String tag, String message) { Log.w(tag, message); }
        @Override public void logInfo(String tag, String message) { Log.i(tag, message); }
        @Override public void logDebug(String tag, String message) { Log.d(tag, message); }
        @Override public void logVerbose(String tag, String message) { Log.v(tag, message); }
        @Override public void logStackTraceWithMessage(String tag, String message, Exception e) {
            Log.e(tag, message, e);
        }
        @Override public void logStackTrace(String tag, Exception e) { Log.e(tag, "stacktrace", e); }
    };
}
