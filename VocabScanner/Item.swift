//
//  Item.swift
//  VocabScanner
//
//  Created by brian.khuong on 28/6/26.
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
