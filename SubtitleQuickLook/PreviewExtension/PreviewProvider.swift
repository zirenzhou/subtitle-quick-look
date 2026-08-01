import Foundation
import QuickLookUI
import UniformTypeIdentifiers
import CoreFoundation

final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    private static let maximumPreviewBytes = 8 * 1_024 * 1_024

    func providePreview(
        for request: QLFilePreviewRequest,
        completionHandler handler: @escaping (QLPreviewReply?, Error?) -> Void
    ) {
        let fileURL = request.fileURL
        let reply = QLPreviewReply(
            dataOfContentType: .plainText,
            contentSize: CGSize(width: 800, height: 1_000)
        ) { reply in
            let didAccess = fileURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }

            let result = try Self.loadText(from: fileURL)
            reply.stringEncoding = .utf8
            reply.title = fileURL.lastPathComponent
            return Data(result.utf8)
        }

        handler(reply, nil)
    }

    private static func loadText(from url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let data = try handle.read(upToCount: maximumPreviewBytes + 1) ?? Data()
        let wasTruncated = data.count > maximumPreviewBytes
        let previewData = wasTruncated ? data.prefix(maximumPreviewBytes) : data[...]

        guard var text = decode(Data(previewData)) else {
            throw PreviewError.unsupportedEncoding
        }

        if wasTruncated {
            text += "\n\n—— 预览已在 8 MiB 处截断 ——"
        }
        return text
    }

    private static func decode(_ data: Data) -> String? {
        let gb18030 = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(0x0632) // kCFStringEncodingGB_18030_2000
            )
        )
        let encodings: [String.Encoding] = [
            .utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            .utf32,
            .utf32LittleEndian,
            .utf32BigEndian,
            gb18030,
            .isoLatin1
        ]

        for encoding in encodings {
            if let string = String(data: data, encoding: encoding) {
                return string
            }
        }
        return nil
    }
}

private enum PreviewError: LocalizedError {
    case unsupportedEncoding

    var errorDescription: String? {
        "无法识别该文件的文本编码。"
    }
}
