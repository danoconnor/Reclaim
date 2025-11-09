//
//  Item.swift
//  PhotoCleanup
//
//  Created by Dan O'Connor on 11/8/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
