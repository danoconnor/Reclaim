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
        // QuickXorHash is specific to Microsoft, hard to verify with standard tools without a reference implementation.
        // We can at least verify it produces a stable output.
        let data = "hello".data(using: .utf8)!
        let hash1 = HashUtils.quickXorHash(of: data)
        let hash2 = HashUtils.quickXorHash(of: data)
        XCTAssertEqual(hash1, hash2)
        XCTAssertFalse(hash1.isEmpty)
    }
}
