//
//  HashUtils.swift
//  PhotoCleanup
//
//  Created by Dan O'Connor on 12/3/25.
//

import Foundation
import CryptoKit

struct HashUtils {
    static func sha256Hex(of data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    static func sha1Hex(of data: Data) -> String {
        #if canImport(CryptoKit)
        // CryptoKit doesn't provide SHA1, so we implement a lightweight pure Swift SHA1 here.
        return Sha1.computeHex(data: data)
        #else
        return Sha1.computeHex(data: data)
        #endif
    }

    static func quickXorHash(of data: Data) -> String {
        // Implementation inspired by OneDrive quickXorHash algorithm specs.
        // quickXorHash produces a Base64 string from a 160-bit result.
        var arr = [UInt8](repeating: 0, count: 20) // 160 bits
        let bytes = [UInt8](data)
        for (index, b) in bytes.enumerated() {
            let offset = index % 20
            arr[offset] = arr[offset] ^ b
        }
        // Convert to Data then base64
        let hashData = Data(arr)
        return hashData.base64EncodedString()
    }
}

// MARK: - SHA1 Implementation (Simplified)

fileprivate enum Sha1 {
    static func computeHex(data: Data) -> String {
        var message = data
        let ml = UInt64(message.count * 8)
        // Append the bit '1' to the message
        message.append(0x80)
        // Append k bits '0', where k is the minimum number >= 0 such that (message length in bits + 64) mod 512 == 0
        while (message.count * 8) % 512 != 448 { message.append(0x00) }
        // Append length as 64-bit big-endian
        var mlBigEndian = ml.bigEndian
        withUnsafeBytes(of: &mlBigEndian) { message.append(contentsOf: $0) }

        // Initialize hash values
        var h0: UInt32 = 0x67452301
        var h1: UInt32 = 0xEFCDAB89
        var h2: UInt32 = 0x98BADCFE
        var h3: UInt32 = 0x10325476
        var h4: UInt32 = 0xC3D2E1F0

        // Process in 512-bit chunks
        let chunkSize = 64
        for chunkStart in stride(from: 0, to: message.count, by: chunkSize) {
            let chunk = message[chunkStart ..< chunkStart + chunkSize]
            var words = [UInt32](repeating: 0, count: 80)
            for i in 0..<16 {
                let start = chunk.index(chunk.startIndex, offsetBy: i * 4)
                let w = chunk[start..<chunk.index(start, offsetBy: 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                words[i] = w
            }
            for i in 16..<80 {
                let val = words[i-3] ^ words[i-8] ^ words[i-14] ^ words[i-16]
                words[i] = (val << 1) | (val >> 31)
            }

            var a = h0, b = h1, c = h2, d = h3, e = h4

            for i in 0..<80 {
                var f: UInt32 = 0, k: UInt32 = 0
                switch i {
                case 0..<20:
                    f = (b & c) | ((~b) & d)
                    k = 0x5A827999
                case 20..<40:
                    f = b ^ c ^ d
                    k = 0x6ED9EBA1
                case 40..<60:
                    f = (b & c) | (b & d) | (c & d)
                    k = 0x8F1BBCDC
                default:
                    f = b ^ c ^ d
                    k = 0xCA62C1D6
                }
                let temp = ((a << 5) | (a >> 27)) &+ f &+ e &+ k &+ words[i]
                e = d
                d = c
                c = (b << 30) | (b >> 2)
                b = a
                a = temp
            }

            h0 = h0 &+ a
            h1 = h1 &+ b
            h2 = h2 &+ c
            h3 = h3 &+ d
            h4 = h4 &+ e
        }

        func wordToBytes(_ word: UInt32) -> [UInt8] {
            return [
                UInt8((word >> 24) & 0xff),
                UInt8((word >> 16) & 0xff),
                UInt8((word >> 8) & 0xff),
                UInt8(word & 0xff)
            ]
        }
        
        let digest = [h0, h1, h2, h3, h4].flatMap(wordToBytes)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
