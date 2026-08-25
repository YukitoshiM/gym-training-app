import AuthenticationServices
import CryptoKit
import Foundation
import Security

enum AIAppleSignIn {
    struct Credential {
        var identityToken: String
        var authorizationCode: String
    }
    static func nonce(length: Int = 32) throws -> String {
        precondition(length > 0)
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length

        while remaining > 0 {
            var bytes = [UInt8](repeating: 0, count: 16)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                throw AIClientError.secureStorageFailed
            }
            for byte in bytes where remaining > 0 {
                guard byte < characters.count * (256 / characters.count) else { continue }
                result.append(characters[Int(byte) % characters.count])
                remaining -= 1
            }
        }
        return result
    }

    static func hashedNonce(_ nonce: String) -> String {
        SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func credential(from result: Result<ASAuthorization, Error>) throws -> Credential {
        let authorization = try result.get()
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8),
              let codeData = credential.authorizationCode,
              let authorizationCode = String(data: codeData, encoding: .utf8) else {
            throw AIClientError.invalidResponse
        }
        return Credential(identityToken: token, authorizationCode: authorizationCode)
    }
}
