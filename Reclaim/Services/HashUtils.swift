//
//  HashUtils.swift
//  Reclaim
//
//  Created by Dan O'Connor on 12/3/25.
//

import Foundation
import CryptoKit

struct HashUtils {
    static nonisolated func sha256Hex(of data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    static nonisolated func sha1Hex(of data: Data) -> String {
        #if canImport(CryptoKit)
        // CryptoKit doesn't provide SHA1, so we implement a lightweight pure Swift SHA1 here.
        return Sha1.computeHex(data: data)
        #else
        return Sha1.computeHex(data: data)
        #endif
    }

    static nonisolated func quickXorHash(of data: Data) -> String {
        // Faithful port of the OneDrive C# QuickXorHash algorithm.
        // Produces a Base64-encoded 160-bit hash that matches OneDrive's quickXorHash.
        var hasher = QuickXorHasher()
        data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            hasher.hashCore(baseAddress.assumingMemoryBound(to: UInt8.self), count: buffer.count)
        }
        let result = hasher.hashFinal()
        return result.base64EncodedString()
    }
}

// MARK: - QuickXorHash (OneDrive algorithm)

/// A faithful Swift port of Microsoft's QuickXorHash algorithm.
/// Reference: https://learn.microsoft.com/en-us/onedrive/developer/code-snippets/quickxorhash
private struct QuickXorHasher {
    private static let bitsInLastCell = 32
    private static let shift: Int = 11
    private static let widthInBits = 160

    // (160 - 1) / 64 + 1 = 3 elements
    private var data: [UInt64] = [0, 0, 0]
    private var lengthSoFar: Int64 = 0
    private var shiftSoFar: Int = 0

    mutating func hashCore(_ array: UnsafePointer<UInt8>, count cbSize: Int) {
        let ibStart = 0
        let currentShift = self.shiftSoFar

        // The bitvector where we'll start xoring
        var vectorArrayIndex = currentShift / 64

        // The position within the bit vector at which we begin xoring
        var vectorOffset = currentShift % 64
        let iterations = min(cbSize, Self.widthInBits)

        for i in 0..<iterations {
            let isLastCell = vectorArrayIndex == self.data.count - 1
            let bitsInVectorCell = isLastCell ? Self.bitsInLastCell : 64

            if vectorOffset <= bitsInVectorCell - 8 {
                // The byte fits entirely within this vector cell
                var j = ibStart + i
                while j < cbSize + ibStart {
                    self.data[vectorArrayIndex] ^= UInt64(array[j]) << vectorOffset
                    j += Self.widthInBits
                }
            } else {
                // The byte spans two vector cells
                let index1 = vectorArrayIndex
                let index2 = isLastCell ? 0 : (vectorArrayIndex + 1)
                let low = bitsInVectorCell - vectorOffset

                var xoredByte: UInt8 = 0
                var j = ibStart + i
                while j < cbSize + ibStart {
                    xoredByte ^= array[j]
                    j += Self.widthInBits
                }
                self.data[index1] ^= UInt64(xoredByte) << vectorOffset
                self.data[index2] ^= UInt64(xoredByte) >> low
            }

            vectorOffset += Self.shift
            while vectorOffset >= bitsInVectorCell {
                vectorArrayIndex = isLastCell ? 0 : vectorArrayIndex + 1
                vectorOffset -= bitsInVectorCell
            }
        }

        // Update the starting position in a circular shift pattern
        self.shiftSoFar = (self.shiftSoFar + Self.shift * (cbSize % Self.widthInBits)) % Self.widthInBits
        self.lengthSoFar += Int64(cbSize)
    }

    func hashFinal() -> Data {
        // Create a byte array big enough to hold all our data
        // (160 - 1) / 8 + 1 = 20 bytes
        var rgb = [UInt8](repeating: 0, count: (Self.widthInBits - 1) / 8 + 1)

        // Copy all bitvectors to the byte array (little-endian)
        for i in 0..<(self.data.count - 1) {
            var value = self.data[i]
            withUnsafeBytes(of: &value) { bytes in
                for j in 0..<8 {
                    rgb[i * 8 + j] = bytes[j]
                }
            }
        }

        // Copy last (partial) cell
        let lastIndex = self.data.count - 1
        let remainingBytes = rgb.count - lastIndex * 8
        var lastValue = self.data[lastIndex]
        withUnsafeBytes(of: &lastValue) { bytes in
            for j in 0..<remainingBytes {
                rgb[lastIndex * 8 + j] = bytes[j]
            }
        }

        // XOR the file length with the least significant bits (little-endian)
        var lengthValue = self.lengthSoFar
        withUnsafeBytes(of: &lengthValue) { lengthBytes in
            let lengthSize = 8 // Int64 is always 8 bytes
            let offset = (Self.widthInBits / 8) - lengthSize
            for i in 0..<lengthSize {
                rgb[offset + i] ^= lengthBytes[i]
            }
        }

        return Data(rgb)
    }
}

// MARK: - SHA1 Implementation (Simplified)

fileprivate enum Sha1 {
    static nonisolated func computeHex(data: Data) -> String {
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
