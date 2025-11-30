//
//  MatchingSensitivity.swift
//  PhotoCleanup
//
//  Created by Dan O'Connor on 11/8/25.
//

import Foundation

public enum MatchingSensitivity: String, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    
    public var displayName: String {
        switch self {
        case .low:
            return "Filename Only"
        case .medium:
            return "Filename + Size"
        case .high:
            return "File Hash"
        }
    }
}
