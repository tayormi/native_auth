import Foundation
import LocalAuthentication
import UIKit

private final class AuthSession {
    let id: String
    let prompt: Bool
    let deadline: TimeInterval
    var result: [String: Any]?
    // These properties are accessed only on the main queue.
    var context: LAContext?
    init(id: String, prompt: Bool, milliseconds: Int) {
        self.id = id
        self.prompt = prompt
        self.deadline = ProcessInfo.processInfo.systemUptime + Double(milliseconds) / 1000
    }
}

private final class AuthBridge {
    static let shared = AuthBridge()
    private let lock = NSLock()
    private var sessions: [String: AuthSession] = [:]
    private var active: String?
    private var observer: NSObjectProtocol?

    private func done(_ status: String, code: String? = nil) -> [String: Any] {
        var result: [String: Any] = ["state": "done", "status": status]
        if let code = code { result["platformCode"] = code }
        return result
    }

    private func mapped(_ error: NSError?) -> String {
        guard let error = error, error.domain == LAError.errorDomain,
              let code = LAError.Code(rawValue: error.code) else { return "nativeError" }
        switch code {
        case .authenticationFailed: return "failed"
        case .userCancel, .userFallback: return "userCancelled"
        case .systemCancel: return "systemCancelled"
        case .appCancel: return "appCancelled"
        case .biometryNotEnrolled: return "notEnrolled"
        case .biometryNotAvailable, .notInteractive: return "unavailable"
        case .biometryLockout: return "lockedOut"
        case .passcodeNotSet: return "passcodeNotSet"
        case .invalidContext: return "invalidConfiguration"
        default: return "nativeError"
        }
    }

    // Completion is idempotent. Cancelled/expired sessions cannot later succeed.
    private func finish(_ session: AuthSession, result: [String: Any]) -> Bool {
        lock.lock()
        guard sessions[session.id] === session, session.result == nil else {
            lock.unlock(); return false
        }
        if result["status"] as? String == "success",
           ProcessInfo.processInfo.systemUptime >= session.deadline {
            session.result = done("timeout")
        } else {
            session.result = result
        }
        if active == session.id { active = nil }
        lock.unlock()
        DispatchQueue.main.async { session.context?.invalidate(); session.context = nil }
        // An abandoned isolate must not retain results indefinitely.
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            if self.sessions[session.id] === session { self.sessions.removeValue(forKey: session.id) }
            self.lock.unlock()
        }
        return true
    }

    private func pending(_ session: AuthSession) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return sessions[session.id] === session && session.result == nil
    }

    private func execute(_ session: AuthSession, args: [String: Any]) {
        guard pending(session) else { return }
        if observer == nil {
            observer = NotificationCenter.default.addObserver(
                forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
            ) { [weak self] _ in
                guard let self = self else { return }
                self.lock.lock()
                let current = self.active.flatMap { self.sessions[$0] }
                self.lock.unlock()
                if let current = current { _ = self.finish(current, result: self.done("systemCancelled")) }
            }
        }
        if session.prompt && UIApplication.shared.applicationState != .active {
            _ = finish(session, result: done("unavailable", code: "app_not_active")); return
        }
        let context = LAContext()
        context.localizedCancelTitle = args["cancelButton"] as? String
        // Biometric-only must not offer an app-controlled password fallback.
        context.localizedFallbackTitle = ""
        session.context = context
        let biometricOnly = args["policy"] as? String == "biometricsOnly"
        let policy: LAPolicy = biometricOnly ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication
        var error: NSError?
        let available = context.canEvaluatePolicy(policy, error: &error)
        if context.biometryType == .faceID,
           (Bundle.main.object(forInfoDictionaryKey: "NSFaceIDUsageDescription") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            _ = finish(session, result: done("invalidConfiguration", code: "missing_face_id_usage_description")); return
        }
        guard available else {
            _ = finish(session, result: done(mapped(error), code: error.map { String($0.code) })); return
        }
        if !session.prompt {
            _ = finish(session, result: done("available")); return
        }
        context.evaluatePolicy(policy, localizedReason: args["reason"] as? String ?? "") { [weak self] success, error in
            guard let self = self else { return }
            var result = self.done(success ? "success" : self.mapped(error as NSError?),
                                   code: (error as NSError?).map { String($0.code) })
            if success { result["method"] = biometricOnly ? "biometric" : "unknown" }
            _ = self.finish(session, result: result)
        }
    }

    func request(_ args: [String: Any]) -> [String: Any] {
        guard let op = args["op"] as? String,
              let id = args["id"] as? String, !id.isEmpty, id.count <= 128 else {
            return done("invalidConfiguration", code: "invalid_request")
        }
        if op == "poll" || op == "cancel" || op == "release" {
            lock.lock()
            let session = sessions[id]
            if op == "poll" {
                guard let session = session else { lock.unlock(); return done("systemCancelled", code: "unknown_request") }
                let result = session.result
                if result != nil { sessions.removeValue(forKey: id) }
                lock.unlock()
                return result ?? ["state": "pending"]
            }
            lock.unlock()
            let cancelled = session.map { finish($0, result: done("appCancelled")) } ?? false
            if op == "release" {
                lock.lock(); sessions.removeValue(forKey: id); lock.unlock()
            }
            return ["cancelled": cancelled]
        }
        guard op == "start" || op == "check",
              let policy = args["policy"] as? String,
              ["biometricsOnly", "biometricsOrDeviceCredential"].contains(policy),
              let timeout = args["timeoutMs"] as? Int, timeout >= 1000, timeout <= 300000 else {
            return done("invalidConfiguration", code: "invalid_options")
        }
        if op == "start" {
            for name in ["reason", "title", "cancelButton"] {
                guard let text = args[name] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      text.utf16.count <= 256, !text.contains("\0") else {
                    return done("invalidConfiguration", code: "invalid_\(name)")
                }
            }
        }
        lock.lock()
        guard sessions[id] == nil, sessions.count < 64, !(op == "start" && active != nil) else {
            lock.unlock(); return done("busy")
        }
        let session = AuthSession(id: id, prompt: op == "start", milliseconds: timeout)
        sessions[id] = session
        if session.prompt { active = id }
        lock.unlock()
        DispatchQueue.main.async { self.execute(session, args: args) }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(timeout)) {
            _ = self.finish(session, result: self.done("timeout"))
        }
        return ["state": "pending"]
    }
}

@_cdecl("DnauthRequest")
public func DnauthRequest(_ input: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    guard let input = input, let data = String(validatingUTF8: input)?.data(using: .utf8),
          let args = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return strdup("{\"state\":\"done\",\"status\":\"invalidConfiguration\"}")
    }
    let result = AuthBridge.shared.request(args)
    guard let encoded = try? JSONSerialization.data(withJSONObject: result),
          let text = String(data: encoded, encoding: .utf8) else { return nil }
    return strdup(text)
}

@_cdecl("DnauthFree")
public func DnauthFree(_ pointer: UnsafeMutablePointer<CChar>?) { free(pointer) }
