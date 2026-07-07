//
//  PNGImageWriter.swift
//  image-depth-test
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum PNGImageWriter {
    nonisolated static func write(_ image: CGImage, to url: URL) throws {
        let canAccessResource = url.startAccessingSecurityScopedResource()
        defer {
            if canAccessResource {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw PNGImageWriterError.cannotCreateDestination
        }

        CGImageDestinationAddImage(destination, image, nil)

        guard CGImageDestinationFinalize(destination) else {
            throw PNGImageWriterError.cannotFinalizeDestination
        }
    }
}

enum PNGImageWriterError: Error {
    case cannotCreateDestination
    case cannotFinalizeDestination
}
