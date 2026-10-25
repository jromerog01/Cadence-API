import CadenceKit
import CoreText
import UIKit

@MainActor enum LocalPDFExporter {
    static func render(_ job: Job) -> Data {
        let text = NSMutableAttributedString(string: job.originalFilename + "\n\n",
                                              attributes: [.font: UIFont.boldSystemFont(ofSize: 20)])
        text.append(NSAttributedString(string: job.segments.map(\.text).joined(separator: "\n\n"),
                                       attributes: [.font: UIFont.systemFont(ofSize: 12)]))
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        return UIGraphicsPDFRenderer(bounds: bounds).pdfData { renderer in
            var offset = 0
            repeat {
                renderer.beginPage()
                let context = renderer.cgContext
                context.saveGState()
                context.translateBy(x: 0, y: bounds.height)
                context.scaleBy(x: 1, y: -1)
                let path = CGPath(rect: bounds.insetBy(dx: 44, dy: 44), transform: nil)
                let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), path, nil)
                CTFrameDraw(frame, context)
                let visible = CTFrameGetVisibleStringRange(frame).length
                context.restoreGState()
                if visible == 0 { break }
                offset += visible
            } while offset < text.length
        }
    }
}
