#!/usr/bin/env swift

import Foundation

struct RGB {
    let value: UInt32

    var luminance: Double {
        let channels = [16, 8, 0].map { shift -> Double in
            let component = Double((value >> UInt32(shift)) & 0xFF) / 255
            return component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }
}

struct ContrastPair {
    let name: String
    let foreground: RGB
    let background: RGB
    let minimum: Double

    var ratio: Double {
        let light = max(foreground.luminance, background.luminance)
        let dark = min(foreground.luminance, background.luminance)
        return (light + 0.05) / (dark + 0.05)
    }
}

let pairs: [ContrastPair] = [
    .init(name: "Royal light primary/page", foreground: .init(value: 0x08172E), background: .init(value: 0xE9EFF7), minimum: 4.5),
    .init(name: "Royal light secondary/page", foreground: .init(value: 0x53647D), background: .init(value: 0xE9EFF7), minimum: 4.5),
    .init(name: "Royal light accent/page", foreground: .init(value: 0x1749D7), background: .init(value: 0xE9EFF7), minimum: 4.5),
    .init(name: "Royal light on accent", foreground: .init(value: 0xF2F5F7), background: .init(value: 0x1749D7), minimum: 4.5),
    .init(name: "Royal dark primary/page", foreground: .init(value: 0xF2F5F7), background: .init(value: 0x061225), minimum: 4.5),
    .init(name: "Royal dark secondary/page", foreground: .init(value: 0xAAB8CF), background: .init(value: 0x061225), minimum: 4.5),
    .init(name: "Royal dark accent/page", foreground: .init(value: 0x5B82FF), background: .init(value: 0x061225), minimum: 4.5),
    .init(name: "Royal dark on accent", foreground: .init(value: 0x08172E), background: .init(value: 0x5B82FF), minimum: 4.5),
    .init(name: "Royal dark card text", foreground: .init(value: 0xF2F5F7), background: .init(value: 0x102444), minimum: 4.5),
    .init(name: "Champagne light primary/page", foreground: .init(value: 0x16120C), background: .init(value: 0xF5F0E2), minimum: 4.5),
    .init(name: "Champagne light secondary/page", foreground: .init(value: 0x665B43), background: .init(value: 0xF5F0E2), minimum: 4.5),
    .init(name: "Champagne light accent/page", foreground: .init(value: 0xB8172D), background: .init(value: 0xF5F0E2), minimum: 4.5),
    .init(name: "Champagne light on accent", foreground: .init(value: 0xFFF9E8), background: .init(value: 0xB8172D), minimum: 4.5),
    .init(name: "Champagne dark primary/page", foreground: .init(value: 0xF4DF9E), background: .init(value: 0x080808), minimum: 4.5),
    .init(name: "Champagne dark secondary/page", foreground: .init(value: 0xB7A36B), background: .init(value: 0x080808), minimum: 4.5),
    .init(name: "Champagne dark accent/page", foreground: .init(value: 0xFF3448), background: .init(value: 0x080808), minimum: 4.5),
    .init(name: "Champagne dark on accent", foreground: .init(value: 0x080808), background: .init(value: 0xFF3448), minimum: 4.5),
    .init(name: "Champagne dark card text", foreground: .init(value: 0xF4DF9E), background: .init(value: 0x1A1710), minimum: 4.5)
]

var hasFailure = false
for pair in pairs {
    let passed = pair.ratio >= pair.minimum
    hasFailure = hasFailure || !passed
    print(String(format: "%@ %.2f %@", pair.name, pair.ratio, passed ? "PASS" : "FAIL"))
}

if hasFailure {
    exit(1)
}
