//
//  OneDriveParserTests.swift
//  ReclaimTests
//
//  Created by Dan O'Connor on 12/3/25.
//

import XCTest
@testable import Reclaim

class OneDriveParserTests: XCTestCase {
    
    func testParseDate_ISO8601WithFractionalSeconds() {
        let dateString = "2023-10-27T10:30:00.123Z"
        let date = OneDriveParser.parseDate(dateString)
        XCTAssertNotNil(date)
    }
    
    func testParseDate_ISO8601WithoutFractionalSeconds() {
        let dateString = "2023-10-27T10:30:00Z"
        let date = OneDriveParser.parseDate(dateString)
        XCTAssertNotNil(date)
    }
    
    func testMakeOneDriveFile_MapsFieldsCorrectly() {
        // Setup
        let json = """
        {
            "id": "123",
            "name": "test.jpg",
            "size": 1024,
            "file": {
                "hashes": {
                    "sha256Hash": "abc"
                }
            },
            "fileSystemInfo": {
                "createdDateTime": "2023-10-27T10:30:00Z",
                "lastModifiedDateTime": "2023-10-27T10:30:00Z"
            },
            "@microsoft.graph.downloadUrl": "http://example.com"
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let graphFile = try! decoder.decode(OneDriveParser.GraphFile.self, from: json)
        
        // Act
        let file = OneDriveParser.makeOneDriveFile(from: graphFile)
        
        // Assert
        XCTAssertNotNil(file)
        XCTAssertEqual(file?.id, "123")
        XCTAssertEqual(file?.name, "test.jpg")
        XCTAssertEqual(file?.size, 1024)
        XCTAssertEqual(file?.hashValue, "abc")
        XCTAssertEqual(file?.hashAlgorithm, .sha256)
    }
    
    func testMakeOneDriveFile_FiltersByDate() {
        // Setup
        let json = """
        {
            "id": "123",
            "name": "test.jpg",
            "size": 1024,
            "file": {},
            "fileSystemInfo": {
                "createdDateTime": "2023-01-01T10:00:00Z"
            }
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let graphFile = try! decoder.decode(OneDriveParser.GraphFile.self, from: json)
        
        let startDate = Date(timeIntervalSince1970: 1700000000) // Late 2023
        
        // Act
        let file = OneDriveParser.makeOneDriveFile(from: graphFile, startDate: startDate)
        
        // Assert
        XCTAssertNil(file, "Should be filtered out because creation date is before start date")
    }
}
