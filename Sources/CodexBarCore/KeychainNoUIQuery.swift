import Foundation

#if os(macOS)
import Security

enum KeychainNoUIQuery {
    static func apply(to query: inout [String: Any]) {
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
    }
}
#endif
