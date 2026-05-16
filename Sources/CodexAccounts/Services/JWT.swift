import Foundation

enum JWTError: Error {
    case invalidFormat
    case base64
}

/// Minimal helpers for inspecting unsigned JWT payloads.
/// We do NOT verify signatures — these tokens come from a trusted local file
/// or directly from auth.openai.com over TLS, and we only read claims for UI.
enum JWT {
    static func parseIdTokenClaims(_ jwt: String) -> IdTokenClaims? {
        guard let payload = decodePayload(jwt) else { return nil }
        let topEmail = payload["email"] as? String
        let profileEmail = (payload["https://api.openai.com/profile"] as? [String: Any])?["email"] as? String
        let auth = payload["https://api.openai.com/auth"] as? [String: Any] ?? [:]

        return IdTokenClaims(
            email: topEmail ?? profileEmail,
            chatgptPlanType: auth["chatgpt_plan_type"] as? String,
            chatgptUserId: (auth["chatgpt_user_id"] as? String) ?? (auth["user_id"] as? String),
            chatgptAccountId: auth["chatgpt_account_id"] as? String,
            chatgptAccountIsFedramp: (auth["chatgpt_account_is_fedramp"] as? Bool) ?? false,
            exp: expirationDate(payload)
        )
    }

    static func parseExpiration(_ jwt: String) -> Date? {
        guard let payload = decodePayload(jwt) else { return nil }
        return expirationDate(payload)
    }

    // MARK: - internals

    private static func expirationDate(_ payload: [String: Any]) -> Date? {
        guard let exp = payload["exp"] as? Double else {
            if let intExp = payload["exp"] as? Int {
                return Date(timeIntervalSince1970: TimeInterval(intExp))
            }
            return nil
        }
        return Date(timeIntervalSince1970: exp)
    }

    private static func decodePayload(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[1].isEmpty else { return nil }
        guard let data = base64URLDecode(String(parts[1])) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func base64URLDecode(_ s: String) -> Data? {
        var b64 = s.replacingOccurrences(of: "-", with: "+")
                   .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - b64.count % 4) % 4
        if pad > 0 { b64 += String(repeating: "=", count: pad) }
        return Data(base64Encoded: b64)
    }

    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
