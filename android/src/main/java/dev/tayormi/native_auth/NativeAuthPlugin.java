package dev.tayormi.native_auth;

import android.app.Activity;
import android.app.Application;
import android.content.Context;
import android.hardware.biometrics.BiometricManager;
import android.hardware.biometrics.BiometricPrompt;
import android.os.Bundle;
import android.os.CancellationSignal;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import java.lang.ref.WeakReference;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;
import org.json.JSONObject;
import io.flutter.embedding.engine.plugins.FlutterPlugin;

/** Native system prompts. No platform channels and no biometric data access. */
public final class NativeAuthPlugin implements FlutterPlugin, Application.ActivityLifecycleCallbacks {
    private static final Object LOCK = new Object();
    private static final Handler MAIN = new Handler(Looper.getMainLooper());
    private static final Map<String, Session> SESSIONS = new HashMap<>();
    private static String active;
    private static Context application;
    private static WeakReference<Activity> activity = new WeakReference<>(null);
    private static native void initializeNative();

    private static final class Session {
        final String id;
        final boolean prompt;
        final long deadline;
        JSONObject result;
        // Main thread only.
        CancellationSignal signal;
        WeakReference<Activity> host = new WeakReference<>(null);
        boolean credentialFallback;
        Session(String id, boolean prompt, int timeout) {
            this.id = id;
            this.prompt = prompt;
            this.deadline = SystemClock.elapsedRealtime() + timeout;
        }
    }

    private static JSONObject done(String status, String code) {
        JSONObject result = new JSONObject();
        try {
            result.put("state", "done").put("status", status);
            if (code != null) result.put("platformCode", code);
        } catch (org.json.JSONException impossible) { throw new AssertionError(impossible); }
        return result;
    }

    private static String status(int code) {
        switch (code) {
            case BiometricPrompt.BIOMETRIC_ERROR_CANCELED: return "systemCancelled";
            case BiometricPrompt.BIOMETRIC_ERROR_USER_CANCELED: return "userCancelled";
            case BiometricPrompt.BIOMETRIC_ERROR_LOCKOUT:
            case BiometricPrompt.BIOMETRIC_ERROR_LOCKOUT_PERMANENT: return "lockedOut";
            case BiometricPrompt.BIOMETRIC_ERROR_NO_BIOMETRICS: return "notEnrolled";
            case BiometricPrompt.BIOMETRIC_ERROR_HW_NOT_PRESENT: return "noHardware";
            case BiometricPrompt.BIOMETRIC_ERROR_HW_UNAVAILABLE:
            case BiometricPrompt.BIOMETRIC_ERROR_SECURITY_UPDATE_REQUIRED: return "unavailable";
            case BiometricPrompt.BIOMETRIC_ERROR_NO_DEVICE_CREDENTIAL: return "passcodeNotSet";
            case BiometricPrompt.BIOMETRIC_ERROR_TIMEOUT: return "timeout";
            default: return "nativeError";
        }
    }

    private static boolean pending(Session session) {
        synchronized (LOCK) { return SESSIONS.get(session.id) == session && session.result == null; }
    }

    private static boolean finish(Session session, JSONObject result) {
        synchronized (LOCK) {
            if (SESSIONS.get(session.id) != session || session.result != null) return false;
            session.result = "success".equals(result.optString("status")) && SystemClock.elapsedRealtime() >= session.deadline
                ? done("timeout", null) : result;
            if (session.id.equals(active)) active = null;
        }
        MAIN.post(() -> { if (session.signal != null) session.signal.cancel(); session.signal = null; });
        MAIN.postDelayed(() -> { synchronized (LOCK) { SESSIONS.remove(session.id, session); } }, 60000);
        return true;
    }

    private static void execute(Session session, JSONObject args) {
        if (!pending(session)) return;
        Context context;
        synchronized (LOCK) { context = application; }
        if (context == null) { finish(session, done("unavailable", "engine_detached")); return; }
        boolean fallback = "biometricsOrDeviceCredential".equals(args.optString("policy"));
        int authenticators = BiometricManager.Authenticators.BIOMETRIC_STRONG;
        if (fallback) authenticators |= BiometricManager.Authenticators.DEVICE_CREDENTIAL;
        try {
            BiometricManager manager = context.getSystemService(BiometricManager.class);
            int available = manager == null ? BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE : manager.canAuthenticate(authenticators);
            if (available != BiometricManager.BIOMETRIC_SUCCESS) {
                finish(session, done(status(available), Integer.toString(available))); return;
            }
            if (!session.prompt) { finish(session, done("available", null)); return; }
            Activity host = activity.get();
            if (host == null || host.isFinishing() || host.isDestroyed() || !host.hasWindowFocus()) {
                finish(session, done("unavailable", "no_foreground_activity")); return;
            }
            session.host = new WeakReference<>(host);
            session.credentialFallback = fallback;
            BiometricPrompt.Builder builder = new BiometricPrompt.Builder(host)
                .setTitle(args.getString("title"))
                .setSubtitle(args.getString("reason"))
                .setAllowedAuthenticators(authenticators);
            if (!fallback) {
                builder.setNegativeButton(args.getString("cancelButton"), host.getMainExecutor(),
                    (dialog, which) -> finish(session, done("userCancelled", null)));
            }
            session.signal = new CancellationSignal();
            builder.build().authenticate(session.signal, host.getMainExecutor(), new BiometricPrompt.AuthenticationCallback() {
                @Override public void onAuthenticationSucceeded(BiometricPrompt.AuthenticationResult result) {
                    JSONObject response = done("success", null);
                    try {
                        String method;
                        switch (result.getAuthenticationType()) {
                            case BiometricPrompt.AUTHENTICATION_RESULT_TYPE_BIOMETRIC: method = "biometric"; break;
                            case BiometricPrompt.AUTHENTICATION_RESULT_TYPE_DEVICE_CREDENTIAL: method = "deviceCredential"; break;
                            default: method = "unknown";
                        }
                        response.put("method", method);
                    } catch (org.json.JSONException impossible) { throw new AssertionError(impossible); }
                    finish(session, response);
                }
                @Override public void onAuthenticationError(int code, CharSequence message) {
                    finish(session, done(status(code), Integer.toString(code)));
                }
                @Override public void onAuthenticationFailed() {
                    // A mismatched scan is nonterminal: the OS prompt permits retry.
                }
            });
        } catch (SecurityException error) {
            finish(session, done("invalidConfiguration", "missing_biometric_permission"));
        } catch (Exception error) {
            finish(session, done("nativeError", "prompt_failed"));
        }
    }

    /** Called through JNI using UTF-8 byte arrays (including non-BMP prompt text). */
    public static byte[] request(byte[] input) {
        JSONObject response;
        try { response = handle(new JSONObject(new String(input, StandardCharsets.UTF_8))); }
        catch (Exception error) { response = done("invalidConfiguration", "invalid_request"); }
        return response.toString().getBytes(StandardCharsets.UTF_8);
    }

    private static JSONObject handle(JSONObject args) throws org.json.JSONException {
        String op = args.getString("op");
        String id = args.getString("id");
        if (id.isEmpty() || id.length() > 128) return done("invalidConfiguration", "invalid_id");
        if (op.equals("poll") || op.equals("cancel") || op.equals("release")) {
            Session session;
            synchronized (LOCK) {
                session = SESSIONS.get(id);
                if (op.equals("poll")) {
                    if (session == null) return done("systemCancelled", "unknown_request");
                    if (session.result == null) return new JSONObject().put("state", "pending");
                    SESSIONS.remove(id);
                    return session.result;
                }
            }
            boolean cancelled = session != null && finish(session, done("appCancelled", null));
            if (op.equals("release")) { synchronized (LOCK) { SESSIONS.remove(id); } }
            return new JSONObject().put("cancelled", cancelled);
        }
        String policy = args.getString("policy");
        int timeout = args.getInt("timeoutMs");
        if ((!op.equals("start") && !op.equals("check")) || timeout < 1000 || timeout > 300000 ||
            (!policy.equals("biometricsOnly") && !policy.equals("biometricsOrDeviceCredential"))) {
            return done("invalidConfiguration", "invalid_options");
        }
        if (op.equals("start")) {
            for (String key : new String[] {"reason", "title", "cancelButton"}) {
                String text = args.getString(key);
                if (text.trim().isEmpty() || text.length() > 256 || text.indexOf('\0') >= 0) {
                    return done("invalidConfiguration", "invalid_" + key);
                }
            }
        }
        Session session;
        synchronized (LOCK) {
            if (SESSIONS.containsKey(id) || SESSIONS.size() >= 64 || (op.equals("start") && active != null)) return done("busy", null);
            session = new Session(id, op.equals("start"), timeout);
            SESSIONS.put(id, session);
            if (session.prompt) active = id;
        }
        MAIN.post(() -> execute(session, args));
        MAIN.postDelayed(() -> finish(session, done("timeout", null)), timeout);
        return new JSONObject().put("state", "pending");
    }

    private static void cancelForHost(Activity host) {
        Session session;
        synchronized (LOCK) { session = SESSIONS.get(active); }
        if (session != null && (host == null || session.host.get() == host)) finish(session, done("systemCancelled", null));
    }

    @Override public void onAttachedToEngine(FlutterPluginBinding binding) {
        System.loadLibrary("native_auth");
        initializeNative();
        synchronized (LOCK) { application = binding.getApplicationContext(); }
        ((Application) binding.getApplicationContext()).registerActivityLifecycleCallbacks(this);
    }
    @Override public void onDetachedFromEngine(FlutterPluginBinding binding) {
        ((Application) binding.getApplicationContext()).unregisterActivityLifecycleCallbacks(this);
        synchronized (LOCK) { application = null; }
        MAIN.post(() -> { cancelForHost(null); activity.clear(); });
    }
    @Override public void onActivityResumed(Activity value) { activity = new WeakReference<>(value); }
    @Override public void onActivityDestroyed(Activity value) { cancelForHost(value); if (activity.get() == value) activity.clear(); }
    @Override public void onActivityStopped(Activity value) {
        Session session;
        synchronized (LOCK) { session = SESSIONS.get(active); }
        // The system credential screen can stop our host; do not cancel that fallback.
        if (session != null && !session.credentialFallback && session.host.get() == value) cancelForHost(value);
    }
    @Override public void onActivityCreated(Activity value, Bundle state) {}
    @Override public void onActivityStarted(Activity value) {}
    @Override public void onActivityPaused(Activity value) {}
    @Override public void onActivitySaveInstanceState(Activity value, Bundle state) {}
}
