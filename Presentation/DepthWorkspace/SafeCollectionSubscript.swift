//
//  SafeCollectionSubscript.swift
//  image-depth-test
//

import Foundation

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
