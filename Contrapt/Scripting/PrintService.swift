//
//  PrintService.swift
//  Contrapt
//
//  Real printing for HyperTalk's print verbs. Cards render offscreen (the same
//  CardView browse mode draws) into a paginated PDF — one card per page at the
//  card's size — and field text paginates via CoreText. The PDF route keeps
//  everything testable headless (page counts, non-empty data); only the final
//  present step touches the print dialog, and the host reaches it through a
//  closure the app wires up (tests capture the PDF instead).
//

import SwiftUI
import CoreText
import CoreGraphics
#if canImport(AppKit)
import AppKit
import PDFKit
#endif

@MainActor
enum PrintService {
    /// A PDF with one page per card index, each the rendered card at natural
    /// size. Invalid indexes are skipped; nil when nothing rendered.
    static func pdfData(stack: Stack, assets: [String: Data], cardIndexes: [Int]) -> Data? {
        let width = stack.cardSize.width, height = stack.cardSize.height
        guard width > 0, height > 0 else { return nil }
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: width, height: height)
        guard let consumer = CGDataConsumer(data: data),
              let pdf = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }
        var pages = 0
        for index in cardIndexes where stack.cards.indices.contains(index) {
            guard let image = cardImage(stack: stack, assets: assets, cardIndex: index) else { continue }
            pdf.beginPDFPage(nil)
            pdf.draw(image, in: mediaBox)
            pdf.endPDFPage()
            pages += 1
        }
        pdf.closePDF()
        return pages > 0 ? data as Data : nil
    }

    /// The card as CardView draws it in browse mode, rendered offscreen.
    static func cardImage(stack: Stack, assets: [String: Data], cardIndex: Int) -> CGImage? {
        let view = CardView(stack: .constant(stack), cardIndex: cardIndex,
                            selectedPartIDs: .constant([]))
            .environment(\.stackAssets, assets)
            .frame(width: stack.cardSize.width, height: stack.cardSize.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2 // crisp text when the PDF page scales up
        return renderer.cgImage
    }

    /// Field text as a paginated US-Letter PDF (1-inch margins), via CoreText.
    static func pdfData(text: String, title: String) -> Data? {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let textBox = page.insetBy(dx: 72, dy: 72)
        let attributed = NSAttributedString(string: text.isEmpty ? " " : text, attributes: [
            .font: CTFontCreateWithName("Helvetica" as CFString, 12, nil),
        ])
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let data = NSMutableData()
        var mediaBox = page
        guard let consumer = CGDataConsumer(data: data),
              let pdf = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }
        var location = 0
        repeat {
            let path = CGPath(rect: textBox, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            pdf.beginPDFPage(nil)
            CTFrameDraw(frame, pdf)
            pdf.endPDFPage()
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else { break }
            location += visible.length
        } while location < attributed.length
        pdf.closePDF()
        return data as Data
    }

    /// Presents the system print dialog for a PDF. macOS prints through
    /// PDFKit's print operation; iOS through the print interaction controller.
    static func present(pdf: Data, jobTitle: String) {
        #if canImport(AppKit)
        guard let document = PDFDocument(data: pdf) else { return }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        guard let operation = document.printOperation(for: info, scalingMode: .pageScaleDownToFit, autoRotate: true) else { return }
        operation.jobTitle = jobTitle
        operation.run()
        #elseif canImport(UIKit)
        // The interpreter invokes host print calls from its background
        // executor (Swift 5 mode doesn't enforce this enum's @MainActor for
        // those synchronous calls), and UIKit's print sheet asserts in its
        // TextKit layout when presented off the main thread — `print card`
        // crashed exactly there on the iPad. Hop explicitly.
        DispatchQueue.main.async {
            let controller = UIPrintInteractionController.shared
            let printInfo = UIPrintInfo(dictionary: nil)
            printInfo.jobName = jobTitle
            controller.printInfo = printInfo
            controller.printingItem = pdf
            controller.present(animated: true)
        }
        #endif
    }
}
