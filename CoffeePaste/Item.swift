//
//  Item.swift
//  CoffeePaste
//
//  Created by ByteDance on 2026/3/23.
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
