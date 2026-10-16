import Foundation
import Security

public final class KeychainHelper: @unchecked Sendable {
    public static let shared = KeychainHelper()

    private let service: String = "com.msjurset.post-mac.env"
    private let lock = NSLock()
    private var inMemoryCache: [String: String] = [:]

    private var onePasswordCache: [String: String] = [:]

    private init() {}

    public static func isOnePasswordReference(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("op://")
    }

    public func setOnePasswordCache(_ value: String, forReference reference: String) {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        onePasswordCache[trimmed] = value
        lock.unlock()
    }

    public func clearOnePasswordCache() {
        lock.lock()
        onePasswordCache.removeAll()
        lock.unlock()
    }

    public func resolveOnePasswordReference(_ reference: String) -> String? {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("op://") else { return nil }

        lock.lock()
        if let cached = onePasswordCache[trimmed] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let candidatePaths = [
            "/opt/homebrew/bin/op",
            "/usr/local/bin/op",
            "/usr/bin/op"
        ]
        guard let opExecutable = candidatePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: opExecutable)
        process.arguments = ["read", "--no-newline", trimmed]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                return nil
            }
            let resolved = String(decoding: outputData, as: UTF8.self)
                .trimmingCharacters(in: .newlines)
            guard !resolved.isEmpty else { return nil }

            lock.lock()
            onePasswordCache[trimmed] = resolved
            lock.unlock()
            return resolved
        } catch {
            return nil
        }
    }

    public func setSecret(_ value: String, forKey key: String) {
        lock.lock()
        inMemoryCache[key] = value
        lock.unlock()

        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let updateAttributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if status == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }

    public func getSecret(forKey key: String) -> String? {
        lock.lock()
        if let cached = inMemoryCache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, let string = String(data: data, encoding: .utf8) {
            lock.lock()
            inMemoryCache[key] = string
            lock.unlock()
            return string
        }

        return nil
    }

    public func deleteSecret(forKey key: String) {
        lock.lock()
        inMemoryCache.removeValue(forKey: key)
        lock.unlock()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }

    public func clearCache() {
        lock.lock()
        inMemoryCache.removeAll()
        onePasswordCache.removeAll()
        lock.unlock()
    }
}
