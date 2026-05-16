import Foundation
import AppKit
import Darwin
import CryptoKit

enum OAuthError: Error, LocalizedError {
    case portsUnavailable
    case stateMismatch
    case missingCode
    case providerError(String)
    case tokenExchangeFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .portsUnavailable: return "本地登录回调端口 1455 和 1457 都不可用。请关闭其他正在登录的 Codex 或 Codex Accounts 窗口后重试。"
        case .stateMismatch: return "登录回调校验失败。请重新点击「添加账户」，不要复用之前打开的登录页面。"
        case .missingCode: return "浏览器没有返回授权码。请重新登录一次。"
        case .providerError(let msg): return "OpenAI 登录返回错误：\(msg)"
        case .tokenExchangeFailed(let msg): return "换取登录凭证失败：\(msg)"
        case .cancelled: return "登录已取消或超时。"
        }
    }
}

/// Codex's registered OAuth client only accepts these two callback ports.
private let kCallbackPorts: [UInt16] = [1455, 1457]

private struct PKCE {
    let verifier: String
    let challenge: String

    static func generate() -> PKCE {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = JWT.base64URLEncode(Data(bytes))
        let digest = SHA256.hash(data: Data(verifier.utf8))
        let challenge = JWT.base64URLEncode(Data(digest))
        return PKCE(verifier: verifier, challenge: challenge)
    }
}

/// Drives the entire OAuth dance: PKCE, browser, loopback callback, code → token exchange.
/// On success, returns an AuthDotJson identical to what `codex login` would write to disk.
final class OAuthLogin {
    private let issuer = "https://auth.openai.com"
    private let clientId = "app_EMoamEEZ73f0CkXaXp7hrann"
    private let scope = "openid profile email offline_access api.connectors.read api.connectors.invoke"
    private let originator = "codex_cli_rs"

    func login() async throws -> AuthDotJson {
        let pkce = PKCE.generate()
        let state = randomBase64URL(byteCount: 32)

        let server = try await LoopbackCallbackServer.bind(ports: kCallbackPorts, expectedState: state)
        defer { server.stop() }

        let redirectURI = "http://localhost:\(server.boundPort)/auth/callback"
        let authURL = buildAuthorizeURL(pkce: pkce, state: state, redirectURI: redirectURI)

        if let url = URL(string: authURL) {
            await MainActor.run { _ = NSWorkspace.shared.open(url) }
        }

        // Race the callback against a timeout and make explicit UI cancellation
        // tear down the local socket immediately.
        let code = try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask { try await server.waitForCode() }
                group.addTask {
                    try await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
                    throw OAuthError.cancelled
                }
                defer { group.cancelAll() }
                guard let first = try await group.next() else {
                    throw OAuthError.cancelled
                }
                return first
            }
        } onCancel: {
            server.stop()
        }
        let tokens = try await exchangeCodeForTokens(code: code, pkce: pkce, redirectURI: redirectURI)
        return makeAuthDotJson(tokens: tokens)
    }

    static func userMessage(for error: Error) -> String {
        if let oauthError = error as? OAuthError {
            return oauthError.localizedDescription
        }
        if let posixError = error as? POSIXError {
            switch posixError.code {
            case .EADDRINUSE:
                return OAuthError.portsUnavailable.localizedDescription
            case .EINVAL:
                return "本地登录回调服务启动失败。请退出其他正在登录的 Codex 或 Codex Accounts 进程后重试；如果仍然失败，重启 Codex Accounts。"
            case .EACCES:
                return "没有权限启动本地登录回调服务。请重新打开 Codex Accounts 后再试。"
            default:
                return "本地登录回调服务遇到网络错误（\(posixError.code.rawValue)）。请稍后重试，或重启 Codex Accounts。"
            }
        }

        let message = error.localizedDescription
        if message.contains("Network.NWError error 22") || message.contains("Invalid argument") {
            return "本地登录回调服务启动失败。请退出其他正在登录的 Codex 或 Codex Accounts 进程后重试；如果仍然失败，重启 Codex Accounts。"
        }
        return message
    }

    // MARK: - URL building

    private func buildAuthorizeURL(pkce: PKCE, state: String, redirectURI: String) -> String {
        let params: [(String, String)] = [
            ("response_type", "code"),
            ("client_id", clientId),
            ("redirect_uri", redirectURI),
            ("scope", scope),
            ("code_challenge", pkce.challenge),
            ("code_challenge_method", "S256"),
            ("id_token_add_organizations", "true"),
            ("codex_cli_simplified_flow", "true"),
            ("state", state),
            ("originator", originator),
        ]
        let qs = params.map { "\($0)=\(urlEncode($1))" }.joined(separator: "&")
        return "\(issuer)/oauth/authorize?\(qs)"
    }

    // MARK: - Token exchange

    private struct TokenResponse: Decodable {
        let id_token: String
        let access_token: String
        let refresh_token: String
    }

    private func exchangeCodeForTokens(code: String, pkce: PKCE, redirectURI: String) async throws -> TokenResponse {
        let url = URL(string: "\(issuer)/oauth/token")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientId,
            "code_verifier": pkce.verifier,
        ].map { "\($0)=\(urlEncode($1))" }.joined(separator: "&")
        req.httpBody = body.data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw OAuthError.tokenExchangeFailed("no HTTP response")
        }
        if !(200..<300).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? "<empty>"
            throw OAuthError.tokenExchangeFailed("HTTP \(http.statusCode): \(text)")
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private func makeAuthDotJson(tokens: TokenResponse) -> AuthDotJson {
        let claims = JWT.parseIdTokenClaims(tokens.id_token)
        let token = TokenData(
            idToken: tokens.id_token,
            accessToken: tokens.access_token,
            refreshToken: tokens.refresh_token,
            accountId: claims?.chatgptAccountId
        )
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return AuthDotJson(
            authMode: "chatgpt",
            openaiApiKey: nil,
            tokens: token,
            lastRefresh: iso.string(from: Date())
        )
    }

    // MARK: - helpers

    private func randomBase64URL(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return JWT.base64URLEncode(Data(bytes))
    }

    private func urlEncode(_ s: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=?#")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}

// MARK: - Loopback HTTP server

/// Minimal one-shot HTTP/1.1 server backing the OAuth redirect_uri.
/// Listens on a local TCP port, waits for one /auth/callback request with valid `state` + `code`,
/// responds with a small HTML success page, and resumes the awaiter.
private final class LoopbackCallbackServer {
    private let socketFD: Int32
    private let queue = DispatchQueue(label: "codex-accounts.oauth-callback")
    private let expectedState: String
    private var continuation: CheckedContinuation<String, Error>?
    private var completedResult: Result<String, Error>?
    private var didResume = false
    private var stopped = false
    private let lock = NSLock()
    let boundPort: UInt16

    private init(socketFD: Int32, boundPort: UInt16, expectedState: String) {
        self.socketFD = socketFD
        self.boundPort = boundPort
        self.expectedState = expectedState
    }

    /// Try each port in order. The OAuth desktop client only has these loopback
    /// callback ports registered, so we cannot fall back to a random free port.
    static func bind(ports: [UInt16], expectedState: String) async throws -> LoopbackCallbackServer {
        var lastError: Error?
        for port in ports {
            do {
                let fd = try Self.openSocket(on: port)
                let server = LoopbackCallbackServer(socketFD: fd, boundPort: port, expectedState: expectedState)
                server.start()
                return server
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError ?? OAuthError.portsUnavailable
    }

    private static func openSocket(on port: UInt16) throws -> Int32 {
        let fd = socket(AF_INET6, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { throw currentPOSIXError() }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        // Bind one IPv6 socket that also accepts IPv4-mapped loopback clients.
        // This avoids the Network.framework EINVAL seen in MenuBarExtra builds
        // and still lets browser redirects to `localhost` use either address family.
        var no: Int32 = 0
        setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &no, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in6()
        addr.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        addr.sin6_family = sa_family_t(AF_INET6)
        addr.sin6_port = port.bigEndian
        addr.sin6_addr = in6addr_any

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.bind(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in6>.size))
            }
        }
        guard bindResult == 0 else {
            let error = currentPOSIXError()
            close(fd)
            throw error
        }

        guard listen(fd, SOMAXCONN) == 0 else {
            let error = currentPOSIXError()
            close(fd)
            throw error
        }
        return fd
    }

    func stop() {
        lock.lock()
        let shouldClose = !stopped
        stopped = true
        lock.unlock()
        if shouldClose {
            shutdown(socketFD, SHUT_RDWR)
            close(socketFD)
        }
        resume(with: .failure(OAuthError.cancelled))
    }

    func waitForCode() async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            lock.lock()
            if let completedResult {
                lock.unlock()
                cont.resume(with: completedResult)
                return
            }
            if didResume {
                lock.unlock()
                cont.resume(throwing: OAuthError.cancelled)
                return
            }
            self.continuation = cont
            lock.unlock()
        }
    }

    private func resume(with result: Result<String, Error>) {
        lock.lock()
        guard !didResume else { lock.unlock(); return }
        didResume = true
        completedResult = result
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(with: result)
    }

    private func start() {
        queue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    private func acceptLoop() {
        while true {
            let clientFD = accept(socketFD, nil, nil)
            if clientFD < 0 {
                if isStopped || errno == EBADF || errno == EINVAL {
                    return
                }
                if errno == EINTR {
                    continue
                }
                resume(with: .failure(Self.currentPOSIXError()))
                return
            }

            handle(clientFD: clientFD)
        }
    }

    private var isStopped: Bool {
        lock.lock()
        let value = stopped
        lock.unlock()
        return value
    }

    private func handle(clientFD: Int32) {
        var yes: Int32 = 1
        setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))

        defer { close(clientFD) }

        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while buffer.count < 65_536 {
            let count = recv(clientFD, &chunk, chunk.count, 0)
            if count > 0 {
                buffer.append(contentsOf: chunk.prefix(count))
                if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                    let headerData = buffer.subdata(in: 0..<headerEnd.lowerBound)
                    processRequest(clientFD: clientFD, header: headerData)
                    return
                }
                continue
            }

            if count == 0 {
                return
            }

            if errno == EINTR {
                continue
            }
            resume(with: .failure(Self.currentPOSIXError()))
            return
        }

        send(clientFD, status: "400 Bad Request", body: "request too large")
    }

    private func processRequest(clientFD: Int32, header: Data) {
        guard let raw = String(data: header, encoding: .utf8),
              let firstLine = raw.components(separatedBy: "\r\n").first else {
            send(clientFD, status: "400 Bad Request", body: "bad request")
            return
        }
        let parts = firstLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2 else {
            send(clientFD, status: "400 Bad Request", body: "bad request")
            return
        }
        let path = String(parts[1])
        guard path.hasPrefix("/auth/callback") else {
            send(clientFD, status: "404 Not Found", body: "not found")
            return
        }
        let comps = URLComponents(string: "http://localhost\(path)")
        let items = comps?.queryItems ?? []
        let code = items.first(where: { $0.name == "code" })?.value
        let state = items.first(where: { $0.name == "state" })?.value
        let errorCode = items.first(where: { $0.name == "error" })?.value
        let errorDesc = items.first(where: { $0.name == "error_description" })?.value

        if let errorCode {
            let msg = errorDesc ?? errorCode
            send(clientFD, status: "200 OK", body: htmlPage(title: "登录失败", body: "OAuth provider returned an error: \(escapeHTML(msg))"))
            resume(with: .failure(OAuthError.providerError(msg)))
            return
        }
        guard state == expectedState else {
            send(clientFD, status: "200 OK", body: htmlPage(title: "登录失败", body: "OAuth state parameter mismatch."))
            resume(with: .failure(OAuthError.stateMismatch))
            return
        }
        guard let code, !code.isEmpty else {
            send(clientFD, status: "200 OK", body: htmlPage(title: "登录失败", body: "Missing authorization code."))
            resume(with: .failure(OAuthError.missingCode))
            return
        }
        send(clientFD, status: "200 OK", body: htmlPage(title: "登录成功", body: "可以关闭此页。"))
        resume(with: .success(code))
    }

    private func send(_ clientFD: Int32, status: String, body: String) {
        let bodyData = Data(body.utf8)
        let headers = [
            "HTTP/1.1 \(status)",
            "Content-Type: text/html; charset=utf-8",
            "Content-Length: \(bodyData.count)",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        var response = Data(headers.utf8)
        response.append(bodyData)
        response.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var sent = 0
            while sent < rawBuffer.count {
                let result = Darwin.send(clientFD, base.advanced(by: sent), rawBuffer.count - sent, 0)
                if result > 0 {
                    sent += result
                    continue
                }
                if result < 0 && errno == EINTR {
                    continue
                }
                return
            }
        }
    }

    private func htmlPage(title: String, body: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="color-scheme" content="light dark">
        <title>\(escapeHTML(title))</title>
        <style>
        :root{color-scheme:light dark;background:#f5f5f7;color:#1d1d1f}
        body{font-family:-apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif;margin:0;min-height:100vh;display:grid;place-items:center;background:#f5f5f7;color:#1d1d1f}
        main{width:min(520px,calc(100vw - 48px))}
        h1{font-size:22px;line-height:1.25;margin:0 0 10px;font-weight:700}
        p{font-size:15px;line-height:1.55;margin:0;color:#3c3c43}
        @media (prefers-color-scheme:dark){
        :root{background:#1c1c1e;color:#f5f5f7}
        body{background:#1c1c1e;color:#f5f5f7}
        p{color:#c7c7cc}
        }
        </style>
        </head>
        <body><main><h1>\(escapeHTML(title))</h1><p>\(escapeHTML(body))</p></main></body>
        </html>
        """
    }

    private func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func currentPOSIXError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
