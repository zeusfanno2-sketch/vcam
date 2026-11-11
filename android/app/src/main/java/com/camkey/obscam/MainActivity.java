package com.camkey.obscam;

import android.app.AlertDialog;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import androidx.annotation.OptIn;
import androidx.appcompat.app.AppCompatActivity;
import androidx.media3.common.MediaItem;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.ui.PlayerView;

import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

@OptIn(markerClass = UnstableApi.class)
public class MainActivity extends AppCompatActivity {

    private static final String DEFAULT_SERVER = "https://ranch-complicated-commander-pink.trycloudflare.com";
    private static final String DEFAULT_STREAM = "http://192.168.1.10:8888/live/test/index.m3u8";

    private SharedPreferences prefs;
    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private final Handler ui = new Handler(Looper.getMainLooper());

    private FrameLayout root;
    private ExoPlayer player;
    private PlayerView playerView;

    private String key = "";
    private String server = DEFAULT_SERVER;
    private long expiresAt = 0;
    private String deviceName = "";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        prefs = getSharedPreferences("camkey", MODE_PRIVATE);
        server = prefs.getString("server", DEFAULT_SERVER);
        key = prefs.getString("key", "");
        expiresAt = prefs.getLong("expiresAt", 0);
        deviceName = prefs.getString("deviceName", deviceName());

        root = new FrameLayout(this);
        root.setBackgroundColor(Color.BLACK);
        setContentView(root, new ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        if (!key.isEmpty() && expiresAt > System.currentTimeMillis()) {
            showPlayer();
            verifyAsync();
        } else {
            showGate("");
        }
    }

    // ---------- device ----------

    private String deviceName() {
        String m = android.os.Build.MANUFACTURER;
        String model = android.os.Build.MODEL;
        return (m + " " + model).trim();
    }

    private String deviceId() {
        String id = Settings.Secure.getString(getContentResolver(), Settings.Secure.ANDROID_ID);
        return id == null ? "unknown" : id;
    }

    private String expiryText() {
        if (expiresAt <= 0) return "—";
        SimpleDateFormat f = new SimpleDateFormat("dd/MM/yyyy", Locale.getDefault());
        return f.format(new Date(expiresAt));
    }

    private int daysLeft() {
        if (expiresAt <= 0) return 0;
        long d = (expiresAt - System.currentTimeMillis()) / 86400000L;
        return (int) Math.max(0, Math.ceil(d));
    }

    // ---------- gate ----------

    private void showGate(String message) {
        releasePlayer();
        root.removeAllViews();

        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(dp(24), dp(48), dp(24), dp(24));

        TextView title = new TextView(this);
        title.setText("OBS Cam");
        title.setTextColor(Color.WHITE);
        title.setTextSize(24);
        title.setTypeface(null, android.graphics.Typeface.BOLD);
        box.addView(title);

        TextView sub = new TextView(this);
        sub.setText("Nhập key để sử dụng");
        sub.setTextColor(0xFF9AA4B2);
        sub.setTextSize(13);
        sub.setPadding(0, dp(4), 0, dp(16));
        box.addView(sub);

        EditText keyInput = input("Key", key);
        keyInput.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS);
        box.addView(keyInput);

        box.addView(kv("Tên thiết bị", deviceName()));
        box.addView(kv("ID thiết bị", deviceId()));
        box.addView(kv("Model", android.os.Build.MODEL));

        TextView msg = new TextView(this);
        msg.setText(message);
        msg.setTextColor(0xFFFFA94D);
        msg.setTextSize(12);
        msg.setPadding(0, dp(12), 0, dp(12));
        box.addView(msg);

        Button btn = new Button(this);
        btn.setText("Kích hoạt");
        btn.setAllCaps(false);
        btn.setOnClickListener(v -> {
            String k = keyInput.getText().toString().trim().toUpperCase();
            if (k.isEmpty()) { msg.setText("Nhập key"); return; }
            activate(k, msg, btn);
        });
        box.addView(btn);

        root.addView(box);
    }

    private EditText input(String hint, String value) {
        EditText e = new EditText(this);
        e.setHint(hint);
        e.setText(value);
        e.setTextColor(Color.WHITE);
        e.setHintTextColor(0xFF6B7280);
        e.setBackgroundColor(0xFF11151C);
        e.setPadding(dp(12), dp(10), dp(12), dp(10));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.topMargin = dp(10);
        e.setLayoutParams(lp);
        return e;
    }

    private View kv(String k, String v) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setPadding(0, dp(6), 0, dp(6));

        TextView a = new TextView(this);
        a.setText(k);
        a.setTextColor(0xFF9AA4B2);
        a.setTextSize(12);

        TextView b = new TextView(this);
        b.setText(v);
        b.setTextColor(Color.WHITE);
        b.setTextSize(12);
        b.setGravity(Gravity.END);
        b.setSingleLine(true);
        b.setEllipsize(android.text.TextUtils.TruncateAt.MIDDLE);

        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        row.addView(a);
        row.addView(b, lp);
        return row;
    }

    private int dp(int v) {
        return Math.round(v * getResources().getDisplayMetrics().density);
    }

    // ---------- api ----------

    private void activate(String k, TextView msg, Button btn) {
        btn.setEnabled(false);
        msg.setText("Đang kiểm tra…");
        io.execute(() -> {
            try {
                JSONObject body = new JSONObject();
                body.put("key", k);
                body.put("udid", deviceId());
                body.put("name", deviceName());

                JSONObject res = post("/api/v1/public/redeem", body);
                boolean ok = res.optBoolean("ok", false);
                if (ok) {
                    key = k;
                    expiresAt = (long) res.optDouble("expiresAt", 0);
                    deviceName = res.optString("deviceName", deviceName);
                    prefs.edit()
                            .putString("key", key)
                            .putString("server", server)
                            .putLong("expiresAt", expiresAt)
                            .putString("deviceName", deviceName)
                            .apply();
                    ui.post(this::showPlayer);
                } else {
                    ui.post(() -> {
                        msg.setText(res.optString("message", "Lỗi"));
                        btn.setEnabled(true);
                    });
                }
            } catch (Exception e) {
                ui.post(() -> {
                    msg.setText("Không kết nối được server");
                    btn.setEnabled(true);
                });
            }
        });
    }

    private void verifyAsync() {
        io.execute(() -> {
            try {
                JSONObject body = new JSONObject();
                body.put("key", key);
                body.put("udid", deviceId());
                JSONObject res = post("/api/v1/public/check", body);
                if (!res.optBoolean("valid", false)) {
                    prefs.edit().remove("key").apply();
                    key = "";
                    ui.post(() -> showGate("Key không hợp lệ hoặc đã hết hạn"));
                }
            } catch (Exception ignored) { }
        });
    }

    private JSONObject post(String path, JSONObject body) throws Exception {
        String base = server.endsWith("/") ? server.substring(0, server.length() - 1) : server;
        HttpURLConnection c = (HttpURLConnection) new URL(base + path).openConnection();
        c.setRequestMethod("POST");
        c.setConnectTimeout(10000);
        c.setReadTimeout(15000);
        c.setDoOutput(true);
        c.setRequestProperty("content-type", "application/json");
        try (OutputStream os = c.getOutputStream()) {
            os.write(body.toString().getBytes("UTF-8"));
        }
        int code = c.getResponseCode();
        BufferedReader r = new BufferedReader(new InputStreamReader(
                code >= 400 ? c.getErrorStream() : c.getInputStream(), "UTF-8"));
        StringBuilder sb = new StringBuilder();
        String line;
        while ((line = r.readLine()) != null) sb.append(line);
        r.close();
        return new JSONObject(sb.toString());
    }

    // ---------- player ----------

    private void showPlayer() {
        root.removeAllViews();

        playerView = new PlayerView(this);
        playerView.setUseController(false);
        root.addView(playerView, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        player = new ExoPlayer.Builder(this).build();
        playerView.setPlayer(player);
        String url = prefs.getString("stream", DEFAULT_STREAM);
        player.setMediaItem(MediaItem.fromUri(url));
        player.prepare();
        player.setPlayWhenReady(true);

        LinearLayout bar = new LinearLayout(this);
        bar.setOrientation(LinearLayout.HORIZONTAL);
        bar.setGravity(Gravity.CENTER_VERTICAL);
        bar.setBackgroundColor(0x73000000);
        bar.setPadding(dp(12), dp(10), dp(12), dp(10));

        TextView days = new TextView(this);
        days.setText(daysLeft() + "d");
        days.setTextColor(0xFFE8ECF4);
        days.setTextSize(12);
        LinearLayout.LayoutParams dlp = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        bar.addView(days, dlp);

        Button info = new Button(this);
        info.setText("ⓘ");
        info.setAllCaps(false);
        info.setTextColor(Color.WHITE);
        info.setBackgroundColor(Color.TRANSPARENT);
        info.setOnClickListener(v -> showInfo());
        bar.addView(info);

        Button edit = new Button(this);
        edit.setText("URL");
        edit.setAllCaps(false);
        edit.setTextColor(Color.WHITE);
        edit.setBackgroundColor(Color.TRANSPARENT);
        edit.setOnClickListener(v -> editStream());
        bar.addView(edit);

        FrameLayout.LayoutParams blp = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        blp.gravity = Gravity.TOP;
        root.addView(bar, blp);

        bar.setOnLongClickListener(v -> { showInfo(); return true; });
    }

    private void editStream() {
        EditText e = new EditText(this);
        e.setText(prefs.getString("stream", DEFAULT_STREAM));
        e.setSingleLine(true);
        new AlertDialog.Builder(this)
                .setTitle("Stream URL")
                .setView(e)
                .setPositiveButton("Lưu", (d, w) -> {
                    prefs.edit().putString("stream", e.getText().toString().trim()).apply();
                    showPlayer();
                })
                .setNegativeButton("Hủy", null)
                .show();
    }

    private void showInfo() {
        String s = "Tên: " + deviceName + "\n"
                + "ID: " + deviceId() + "\n"
                + "Model: " + android.os.Build.MODEL + "\n\n"
                + "Key: " + key + "\n"
                + "Hạn: " + expiryText() + "\n"
                + "Còn lại: " + daysLeft() + " ngày\n\n"
                + "Stream: " + prefs.getString("stream", DEFAULT_STREAM) + "\n"
                + "Phiên bản: 1.0.0";
        new AlertDialog.Builder(this)
                .setTitle("Thông tin")
                .setMessage(s)
                .setPositiveButton("Đóng", null)
                .show();
    }

    private void releasePlayer() {
        if (player != null) {
            player.release();
            player = null;
        }
        if (playerView != null) {
            playerView.setPlayer(null);
            playerView = null;
        }
    }

    @Override
    protected void onDestroy() {
        releasePlayer();
        super.onDestroy();
    }
}
