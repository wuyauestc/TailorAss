//
//  MediaUtils.swift
//  裁缝助手 —— 图片压缩与 PDF 校验（PRD：封面宽≤750px JPEG；PDF≤20MB）
//

import UIKit

enum MediaUtils {

    /// 将相册原图等比缩小到最大宽度并转 JPEG
    /// - Returns: (UIImage, JPEG Data)；原图本身更窄时不放大
    static func compressCover(data: Data,
                              maxWidth: CGFloat = AppConstants.coverMaxWidth,
                              quality: CGFloat = 0.82) -> (UIImage, Data)? {
        guard let image = UIImage(data: data) else { return nil }
        let scaled: UIImage
        if image.size.width > maxWidth {
            let scale = maxWidth / image.size.width
            let newSize = CGSize(width: maxWidth, height: image.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            scaled = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        } else {
            scaled = image
        }
        guard let jpeg = scaled.jpegData(compressionQuality: quality) else { return nil }
        return (scaled, jpeg)
    }

    /// 把 JPEG 数据写入临时文件（上传 CloudKit 时 CKAsset 必须基于文件 URL）
    static func writeToTempFile(data: Data, name: String = UUID().uuidString, ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(name)
            .appendingPathExtension(ext)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// 校验 PDF 大小（≤20MB）
    static func isPDFSizeValid(_ url: URL) -> Bool {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return false }
        return size <= AppConstants.pdfMaxSizeMB * 1024 * 1024
    }

    /// 人类可读文件大小
    static func fileSizeText(_ url: URL) -> String? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
        let mb = Double(size) / 1024.0 / 1024.0
        return String(format: "%.1f MB", mb)
    }
}
