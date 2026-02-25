//
//  HashAlgorithm.swift
//  Reclaim
//
//  Created by Dan O'Connor on 1/7/26.
//

import Foundation

enum HashAlgorithm: String, Codable, Hashable, Sendable {
    case sha256
    case sha1
    case quickXor
}