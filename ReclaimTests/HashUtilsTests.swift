//
//  HashUtilsTests.swift
//  ReclaimTests
//
//  Created by Dan O'Connor on 12/3/25.
//

import XCTest
@testable import Reclaim

class HashUtilsTests: XCTestCase {
    
    func testSHA256Hex() {
        let data = "hello".data(using: .utf8)!
        let hash = HashUtils.sha256Hex(of: data)
        // echo -n "hello" | shasum -a 256
        XCTAssertEqual(hash, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }
    
    func testSHA1Hex() {
        let data = "hello".data(using: .utf8)!
        let hash = HashUtils.sha1Hex(of: data)
        // echo -n "hello" | shasum -a 1
        XCTAssertEqual(hash, "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d")
    }
    
    func testQuickXorHash() {
        // Verified against the C# reference implementation of QuickXorHash.
        let data = "hello".data(using: .utf8)!
        let hash1 = HashUtils.quickXorHash(of: data)
        let hash2 = HashUtils.quickXorHash(of: data)
        XCTAssertEqual(hash1, hash2)
        XCTAssertFalse(hash1.isEmpty)
        // Expected value from the C# reference implementation
        XCTAssertEqual(hash1, "aCgDG9jwBgAAAAAABQAAAAAAAAA=")
    }

    func testQuickXorHashEmpty() {
        let data = Data()
        let hash = HashUtils.quickXorHash(of: data)
        // Empty data should produce a hash of all zeros (20 zero bytes, base64 = "AAAAAAAAAAAAAAAAAAAAAAAAAAA=")
        XCTAssertEqual(hash, "AAAAAAAAAAAAAAAAAAAAAAAAAAA=")
    }

    func testQuickXorHashLargerData() {
        // Test with data larger than WidthInBits (160 bytes) to exercise the striding loop
        let data = Data(repeating: 0xAB, count: 500)
        let hash1 = HashUtils.quickXorHash(of: data)
        let hash2 = HashUtils.quickXorHash(of: data)
        XCTAssertEqual(hash1, hash2)
        XCTAssertFalse(hash1.isEmpty)
    }

    func testQuickXorHashMatchesOneDrive() throws {
        // Load structured test data containing base64-encoded file samples and their expected OneDrive quickXorHash values.
        // Add more entries to quickXorHashTestData.json to expand coverage.
        let url = try XCTUnwrap(
            Bundle(for: type(of: self)).url(forResource: "quickXorHashTestData", withExtension: "json"),
            "quickXorHashTestData.json not found in test bundle"
        )
        let jsonData = try Data(contentsOf: url)

        struct TestSample: Decodable {
            let name: String
            let base64Data: String
            let expectedQuickXorHash: String
        }

        let samples = try JSONDecoder().decode([TestSample].self, from: jsonData)
        XCTAssertFalse(samples.isEmpty, "Test data file contains no samples")

        for sample in samples {
            let fileData = try XCTUnwrap(
                Data(base64Encoded: sample.base64Data, options: .ignoreUnknownCharacters),
                "Failed to decode base64 data for sample '\(sample.name)'"
            )
            let hash = HashUtils.quickXorHash(of: fileData)
            XCTAssertEqual(hash, sample.expectedQuickXorHash, "QuickXorHash mismatch for sample '\(sample.name)'")
        }
    }
}
