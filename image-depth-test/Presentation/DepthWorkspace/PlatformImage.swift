//
//  PlatformImage.swift
//  image-depth-test
//

import SwiftUI

extension Image {
    init(platformImage: NSImage) {
        self.init(nsImage: platformImage)
    }
}
