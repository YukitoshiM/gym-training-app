#!/usr/bin/env swift

import Foundation
import Security

func fail(_ message: String, status: OSStatus? = nil) -> Never {
    if let status,
       let detail = SecCopyErrorMessageString(status, nil) as String? {
        FileHandle.standardError.write(Data("error: \(message): \(detail)\n".utf8))
    } else {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    }
    exit(1)
}

guard CommandLine.arguments.count == 6, CommandLine.arguments[1] == "set" else {
    fail("usage: keychain_secret.swift set SERVICE ACCOUNT LABEL COMMENT")
}

let service = CommandLine.arguments[2]
let account = CommandLine.arguments[3]
let label = CommandLine.arguments[4]
let comment = CommandLine.arguments[5]
let secret = FileHandle.standardInput.readDataToEndOfFile()

guard !secret.isEmpty else {
    fail("secret input is empty")
}

let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: service,
    kSecAttrAccount as String: account,
]
let updates: [String: Any] = [
    kSecValueData as String: secret,
    kSecAttrLabel as String: label,
    kSecAttrComment as String: comment,
]

let updateStatus = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
if updateStatus == errSecSuccess {
    exit(0)
}
guard updateStatus == errSecItemNotFound else {
    fail("could not update Keychain item", status: updateStatus)
}

var attributes = query
updates.forEach { attributes[$0.key] = $0.value }
attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

let addStatus = SecItemAdd(attributes as CFDictionary, nil)
guard addStatus == errSecSuccess else {
    fail("could not add Keychain item", status: addStatus)
}
