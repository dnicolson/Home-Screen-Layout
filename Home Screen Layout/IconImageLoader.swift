import Compression
import CoreGraphics
import Foundation
import MetalKit

enum IconError: Error {
    case fileTooSmall
    case badSignature
    case missingChunk(String)
    case decompressionFailed
}

// MARK: - Helpers

private func readU32LE(_ data: Data, at offset: Int) -> UInt32 {
    var v: UInt32 = 0
    _ = data[data.startIndex + offset ..< data.startIndex + offset + 4]
        .withUnsafeBytes { memcpy(&v, $0.baseAddress!, 4) }
    return v.littleEndian
}

private func readU64LE(_ data: Data, at offset: Int) -> UInt64 {
    var v: UInt64 = 0
    _ = data[data.startIndex + offset ..< data.startIndex + offset + 8]
        .withUnsafeBytes { memcpy(&v, $0.baseAddress!, 8) }
    return v.littleEndian
}

private func maxASTCDataSize(width: Int, height: Int) -> Int {
    let blocksX = Int(ceil(Double(width) / 4.0))
    let blocksY = Int(ceil(Double(height) / 4.0))
    return blocksX * blocksY * 16
}

// MARK: - AAPL Container

struct AAPLChunk {
    let type: String
    let body: Data
}

struct AAPLContainer {
    let width: Int
    let height: Int
    let chunks: [AAPLChunk]
    let endOffset: Int

    var lzfsBody: Data {
        chunks.first(where: { $0.type == "LZFS" })!.body
    }
}

final class IconImageLoader {
    private let resourceURLs: [URL]

    init(resourceNames: [String]) throws {
        self.resourceURLs = try resourceNames.map { resourceName in
            guard let url = Bundle.main.url(forResource: resourceName, withExtension: nil) else {
                throw NSError(
                    domain: "IconASTCReader",
                    code: 8,
                    userInfo: [NSLocalizedDescriptionKey: "Missing resource \(resourceName) in app bundle"]
                )
            }
            return url
        }
    }

    init(directoryPath: String) throws {
        let directoryURL = URL(fileURLWithPath: directoryPath, isDirectory: true)
        self.resourceURLs = try Self.resourceURLs(in: directoryURL)
    }

    convenience init(from directoryPath: String) throws {
        try self.init(directoryPath: directoryPath)
    }

    
    private func parseContainer(_ data: Data, at offset: Int) throws -> AAPLContainer {
        let sig: [UInt8] = [0x41,0x41,0x50,0x4C,0x0D,0x0A,0x1A,0x0A]
        guard offset + 8 <= data.count,
              data[offset ..< offset+8].elementsEqual(sig) else {
            throw IconError.badSignature
        }

        var pos = offset + 8
        var chunks = [AAPLChunk]()

        while pos + 8 <= data.count {
            let length = Int(readU32LE(data, at: pos))
            let typeSlice = data[pos+4 ..< pos+8]
            guard let type = String(bytes: typeSlice, encoding: .ascii) else { break }
            let bodyStart = pos + 8
            let bodyEnd   = bodyStart + length
            guard bodyEnd <= data.count else { throw IconError.badSignature }
            chunks.append(AAPLChunk(type: type, body: data[bodyStart ..< bodyEnd]))
            pos = bodyEnd
            if type == "END " { break }
        }

        guard let head = chunks.first(where: { $0.type == "HEAD" }) else {
            throw IconError.missingChunk("HEAD")
        }
        guard chunks.contains(where: { $0.type == "LZFS" }) else {
            throw IconError.missingChunk("LZFS")
        }

        let width  = Int(readU32LE(head.body, at: 24))
        let height = Int(readU32LE(head.body, at: 28))

        return AAPLContainer(width: width, height: height,
                             chunks: chunks, endOffset: pos)
    }

    private func decompressBestEffort(_ data: Data, expectedMaxSize: Int) throws -> Data {
        let algorithms: [compression_algorithm] = [
            COMPRESSION_LZFSE,
            COMPRESSION_LZ4,
            COMPRESSION_ZLIB,
            COMPRESSION_LZMA
        ]
        let minDecodedSize = max(64, expectedMaxSize / 4)

        var candidates = [data]
        if data.count >= 8 {
            let start = data.startIndex + 4
            let end = data.startIndex + 8
            let magic = String(bytes: data[start..<end], encoding: .ascii) ?? ""
            if magic == "bvx2" || magic == "bvx1" {
                let start = data.startIndex + 4
                let end = data.startIndex + data.count
                candidates.insert(data.subdata(in: start..<end), at: 0)
            }
        }

        for candidate in candidates {
            for algorithm in algorithms {
                var output = [UInt8](repeating: 0, count: expectedMaxSize)
                let decodedSize = candidate.withUnsafeBytes { src in
                    guard let srcPtr = src.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
                    return output.withUnsafeMutableBytes { dst in
                        guard let dstPtr = dst.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
                        return compression_decode_buffer(
                            dstPtr,
                            expectedMaxSize,
                            srcPtr,
                            candidate.count,
                            nil,
                            algorithm
                        )
                    }
                }

                if decodedSize >= minDecodedSize {
                    if decodedSize < expectedMaxSize {
                        output.removeLast(expectedMaxSize - decodedSize)
                    }
                    return Data(output)
                }
            }
        }

        throw IconError.decompressionFailed
    }

    func iconHasLayer(atPath path: String, width: Int, height: Int) throws -> Bool {
        let url = URL(fileURLWithPath: path)
        let file = try Data(contentsOf: url)

        if file.count < 56 { throw IconError.fileTooSmall }
        let imageOffset = Int(readU64LE(file, at: 0x18))

        let c1 = try parseContainer(file, at: imageOffset)
        if c1.width == width && c1.height == height { return true }

        if c1.endOffset + 8 < file.count,
           let c2 = try? parseContainer(file, at: c1.endOffset) {
            return c2.width == width && c2.height == height
        }

        return false
    }

    
    func loadLatestASTCImage(width: Int, height: Int) throws -> CGImage {
        let reader = try IconASTCReader()
        let finalURL = try selectLatestURL(width: width, height: height)
        let fileData = try Data(contentsOf: finalURL)

        var payloadData = fileData
        var astcWidth = width
        var astcHeight = height
        if fileData.count >= 0x20 {
            let imageOffset = Int(readU64LE(fileData, at: 0x18))
            if imageOffset + 8 <= fileData.count,
               let container = try? parseContainer(fileData, at: imageOffset) {
                astcWidth = container.width
                astcHeight = container.height
                let expectedMaxSize = maxASTCDataSize(width: container.width, height: container.height)
                payloadData = try decompressBestEffort(container.lzfsBody, expectedMaxSize: expectedMaxSize)
            }
        }

        let texture = try reader.loadIconBGRA8(
            from: payloadData,
            name: finalURL.lastPathComponent,
            width: astcWidth,
            height: astcHeight
        )
        return try reader.makeCGImage(from: texture)
    }

    private func selectLatestURL(width: Int, height: Int) throws -> URL {
        let fileManager = FileManager.default
        var selectedURL: URL?
        var selectedDate = Date.distantPast

        for url in resourceURLs {
            let hasLayer = try iconHasLayer(atPath: url.path, width: width, height: height)
            guard hasLayer else {
                continue
            }

            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            let modDate = (attributes[.modificationDate] as? Date) ?? .distantPast
            if modDate > selectedDate {
                selectedDate = modDate
                selectedURL = url
            }
        }

        guard let finalURL = selectedURL else {
            throw NSError(
                domain: "IconASTCReader",
                code: 9,
                userInfo: [NSLocalizedDescriptionKey: "No ASTC resource with \(width)x\(height) resolution"]
            )
        }

        return finalURL
    }

    private static func resourceURLs(in directoryURL: URL) throws -> [URL] {
        let fileManager = FileManager.default
        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return urls.filter { url in
            (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
        }
    }

}

private final class IconASTCReader {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw NSError(domain: "IconASTCReader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Metal device unavailable"])
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw NSError(domain: "IconASTCReader", code: 2, userInfo: [NSLocalizedDescriptionKey: "Command queue unavailable"])
        }
        guard let library = device.makeDefaultLibrary() else {
            throw NSError(domain: "IconASTCReader", code: 10, userInfo: [NSLocalizedDescriptionKey: "Metal library unavailable"])
        }

        guard let vertexFunction = library.makeFunction(name: "fullscreenVertex"),
              let fragmentFunction = library.makeFunction(name: "textureBlitFragment") else {
            throw NSError(domain: "IconASTCReader", code: 11, userInfo: [NSLocalizedDescriptionKey: "Metal shader functions missing"])
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        self.device = device
        self.commandQueue = commandQueue
        self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }

    func loadIconBGRA8(from data: Data, name: String, width: Int, height: Int) throws -> MTLTexture {
        let loader = MTKTextureLoader(device: device)
        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: false,
            .textureStorageMode: MTLStorageMode.private.rawValue
        ]
        let sourceTexture: MTLTexture
        do {
            sourceTexture = try loader.newTexture(data: data, options: options)
        } catch {
            sourceTexture = try loadASTCTexture(
                from: data,
                using: loader,
                options: options,
                name: name,
                width: width,
                height: height
            )
        }

        let destinationDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: sourceTexture.width,
            height: sourceTexture.height,
            mipmapped: false
        )
        destinationDescriptor.usage = [.renderTarget, .shaderRead]
        guard let destinationTexture = device.makeTexture(descriptor: destinationDescriptor) else {
            throw NSError(domain: "IconASTCReader", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate destination texture"])
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw NSError(domain: "IconASTCReader", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create command buffer"])
        }

        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = destinationTexture
        passDescriptor.colorAttachments[0].loadAction = .dontCare
        passDescriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else {
            throw NSError(domain: "IconASTCReader", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to create render encoder"])
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(sourceTexture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if let error = commandBuffer.error {
            throw error
        }

        return destinationTexture
    }

    private func loadASTCTexture(
        from data: Data,
        using loader: MTKTextureLoader,
        options: [MTKTextureLoader.Option: Any],
        name: String,
        width: Int,
        height: Int
    ) throws -> MTLTexture {
        if data.count >= 16, data.starts(with: [0x13, 0xAB, 0xA1, 0x5C]) {
            return try loader.newTexture(data: data, options: options)
        }

        let candidateSizes: [(blockX: Int, blockY: Int)] = [
            (4, 4), (5, 5), (6, 6), (8, 8), (10, 10), (12, 12)
        ]
        for candidate in candidateSizes {
            let blocksX = Int(ceil(Double(width) / Double(candidate.blockX)))
            let blocksY = Int(ceil(Double(height) / Double(candidate.blockY)))
            let expected = blocksX * blocksY * 16
            if data.count == expected {
                let header = makeASTCHeader(
                    blockX: candidate.blockX,
                    blockY: candidate.blockY,
                    width: width,
                    height: height
                )
                var wrapped = Data()
                wrapped.append(header)
                wrapped.append(data)
                return try loader.newTexture(data: wrapped, options: options)
            }
        }

        throw NSError(
            domain: "IconASTCReader",
            code: 12,
            userInfo: [NSLocalizedDescriptionKey: "Unsupported ASTC payload size for \(name)"]
        )
    }

    private func makeASTCHeader(blockX: Int, blockY: Int, width: Int, height: Int) -> Data {
        var header = Data()
        header.append(contentsOf: [0x13, 0xAB, 0xA1, 0x5C])
        header.append(UInt8(blockX))
        header.append(UInt8(blockY))
        header.append(1)
        header.append(contentsOf: [
            UInt8(width & 0xFF),
            UInt8((width >> 8) & 0xFF),
            UInt8((width >> 16) & 0xFF)
        ])
        header.append(contentsOf: [
            UInt8(height & 0xFF),
            UInt8((height >> 8) & 0xFF),
            UInt8((height >> 16) & 0xFF)
        ])
        header.append(contentsOf: [1, 0, 0])
        return header
    }

    func makeCGImage(from texture: MTLTexture) throws -> CGImage {
        let width = texture.width
        let height = texture.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let byteCount = bytesPerRow * height
        var bytes = [UInt8](repeating: 0, count: byteCount)

        let region = MTLRegionMake2D(0, 0, width, height)
        texture.getBytes(&bytes, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)

        guard let dataProvider = CGDataProvider(data: NSData(bytes: &bytes, length: bytes.count)) else {
            throw NSError(domain: "IconASTCReader", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to create data provider"])
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let alphaInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(alphaInfo)

        guard let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: dataProvider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            throw NSError(domain: "IconASTCReader", code: 7, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage"])
        }

        return image
    }
}
