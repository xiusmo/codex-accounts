import Foundation

enum RawErrorText {
    static func string(_ error: Error) -> String {
        if case let decoding as DecodingError = error {
            return String(describing: decoding)
        }

        let described = String(describing: error)
        let nsError = error as NSError
        if !nsError.userInfo.isEmpty {
            var parts = [described.isEmpty ? "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)" : described]
            parts.append(String(describing: nsError.userInfo))
            return parts.joined(separator: "\n")
        }
        return described.isEmpty ? "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)" : described
    }

    static func http(statusCode: Int, body: Data) -> String {
        "HTTP \(statusCode): \(bodyString(body))"
    }

    static func bodyString(_ data: Data) -> String {
        if data.isEmpty { return "<empty>" }
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return text
        }
        return "<\(data.count) non-utf8 bytes>"
    }
}
