import Foundation
import SwiftUI
import SwiftData
#if os(macOS)
  import AppKit
#else
  import UIKit
#endif
import BrickCore

#if os(macOS)
  private extension NSFont {
    var lineHeight: CGFloat {
      ascender - descender + leading
    }
  }
#endif

#if os(macOS)
  private typealias PlatformFont = NSFont
#else
  private typealias PlatformFont = UIFont
#endif

struct SetLabelPreviewView: View {
  let brickSet: BrickSet
  var labelSize: CGSize?
  var displayScale: CGFloat = LabelMetrics.previewScale
  var bagIndex: Int? = nil
  var bagCount: Int = 1

  private var resolvedLabelSize: CGSize {
    labelSize ?? LabelMetrics.labelSize(for: brickSet)
  }

  var body: some View {
    ScaledLabelCanvas(
      brickSet: brickSet,
      labelSize: resolvedLabelSize,
      scale: displayScale,
      bagIndex: bagIndex,
      bagCount: bagCount
    )
        .padding()
        .background(.white)
    }
}

private struct SetLabelCanvas: View {
    let brickSet: BrickSet
    var bagIndex: Int? = nil
    var bagCount: Int = 1

    var body: some View {
        ZStack {
            Color.white

            VStack(alignment: .leading, spacing: LabelMetrics.verticalSpacing) {
                Text(brickSet.setNumber)
                    .font(LabelMetrics.identifierFont)
                    .lineLimit(1)
                    .minimumScaleFactor(LabelMetrics.identifierMinimumScale)
                    .fixedSize(horizontal: false, vertical: true)

                ViewThatFits {
                    Text(brickSet.name)
                        .font(LabelMetrics.titleFont)
                        .lineLimit(1)
                        .minimumScaleFactor(LabelMetrics.titleSingleLineMinimumScale)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(brickSet.name)
                        .font(LabelMetrics.titleMultiLineFont)
                        .lineLimit(2)
                        .minimumScaleFactor(LabelMetrics.titleMultiLineMinimumScale)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, LabelMetrics.horizontalPadding)
            .padding(.vertical, LabelMetrics.verticalPadding)
        }
        .overlay(alignment: .topTrailing) {
            if let bagIndex, bagCount > 1 {
                Text("\(bagIndex)/\(bagCount)")
                    .font(LabelMetrics.bagFont)
                    .foregroundStyle(.black)
                    .padding(.top, LabelMetrics.bagInset)
                    .padding(.trailing, LabelMetrics.bagInset)
            }
        }
    }
}

private struct ScaledLabelCanvas: View {
    let brickSet: BrickSet
    let labelSize: CGSize
    let scale: CGFloat
    var bagIndex: Int? = nil
    var bagCount: Int = 1

    var body: some View {
        let canvas = SetLabelCanvas(brickSet: brickSet, bagIndex: bagIndex, bagCount: bagCount)
            .frame(width: labelSize.width, height: labelSize.height)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
                    .foregroundStyle(Color.gray.opacity(0.4))
            )

        if scale == 1 {
            canvas
        } else {
            canvas
                .scaleEffect(scale)
                .frame(
                    width: labelSize.width * scale,
                    height: labelSize.height * scale,
                    alignment: .center
                )
        }
    }
}

private enum LabelMetrics {
  static let labelWidthMillimeters: CGFloat = 62
  static let fallbackHeightMillimeters: CGFloat = 20
  static let previewScale: CGFloat = 2.0

  static let horizontalPadding: CGFloat = 6
  static let verticalPadding: CGFloat = 6
  static let verticalSpacing: CGFloat = 4

  private static let identifierFontSize: CGFloat = 14
  private static let identifierFontWeight: Font.Weight = .semibold

  private static let titleSingleLineFontSize: CGFloat = 16
  private static let titleSingleLineFontWeight: Font.Weight = .regular

  private static let titleMultiLineFontSize: CGFloat = 14
  private static let titleMultiLineFontWeight: Font.Weight = .regular
  private static let bagFontSize: CGFloat = 10
  private static let bagFontWeight: Font.Weight = .semibold
  static let bagInset: CGFloat = 4

  static var identifierFont: Font {
    swiftUIFont(size: identifierFontSize, weight: identifierFontWeight)
  }

  static var titleFont: Font {
    swiftUIFont(size: titleSingleLineFontSize, weight: titleSingleLineFontWeight)
  }

  static var titleMultiLineFont: Font {
    swiftUIFont(size: titleMultiLineFontSize, weight: titleMultiLineFontWeight)
  }

  static var bagFont: Font {
    swiftUIFont(size: bagFontSize, weight: bagFontWeight)
  }

  static func labelSize(for brickSet: BrickSet) -> CGSize {
    let width = labelWidthPoints
    let contentWidth = max(1, width - (horizontalPadding * 2))

    let numberHeight = textHeight(
      for: brickSet.setNumber,
      font: identifierNativeFont,
      constrainedTo: contentWidth,
      maxLines: 1
    )

    let nameHeight = nameHeight(for: brickSet.name, constrainedTo: contentWidth)

    let spacing = brickSet.name.isEmpty ? 0 : verticalSpacing
    let totalHeight = verticalPadding * 2 + numberHeight + spacing + nameHeight
    let fallbackHeight = points(fromMillimeters: fallbackHeightMillimeters)

    return CGSize(width: width, height: max(totalHeight, fallbackHeight))
  }

  static let identifierMinimumScale: CGFloat = 0.75
  static let titleSingleLineMinimumScale: CGFloat = 0.8
  static let titleMultiLineMinimumScale: CGFloat = 0.75

  private static var identifierNativeFont: PlatformFont {
    platformFont(size: identifierFontSize, weight: identifierFontWeight)
  }

  private static var titleSingleLineNativeFont: PlatformFont {
    platformFont(size: titleSingleLineFontSize, weight: titleSingleLineFontWeight)
  }

  private static var titleMultiLineNativeFont: PlatformFont {
    platformFont(size: titleMultiLineFontSize, weight: titleMultiLineFontWeight)
  }

  private static func nameHeight(for text: String, constrainedTo width: CGFloat) -> CGFloat {
    guard !text.isEmpty else { return 0 }

    let singleLineWidth = textWidth(for: text, font: titleSingleLineNativeFont)
    if singleLineWidth <= width {
      return titleSingleLineNativeFont.lineHeight
    }

    return textHeight(
      for: text,
      font: titleMultiLineNativeFont,
      constrainedTo: width,
      maxLines: 2
    )
  }

  private static var labelWidthPoints: CGFloat {
    points(fromMillimeters: labelWidthMillimeters)
  }

  static func points(fromMillimeters millimeters: CGFloat) -> CGFloat {
    millimeters * 72.0 / 25.4
  }

  private static func textHeight(
    for text: String,
    font: PlatformFont,
    constrainedTo width: CGFloat,
    maxLines: Int
  ) -> CGFloat {
    guard !text.isEmpty else { return 0 }
    let boundingSize = CGSize(width: width, height: .greatestFiniteMagnitude)
    let rect = attributedString(text, font: font).boundingRect(
      with: boundingSize,
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      context: nil
    )
    let measuredHeight = ceil(rect.height)
    let maxHeight = ceil(font.lineHeight * CGFloat(maxLines))
    return min(measuredHeight, maxHeight)
  }

  private static func textWidth(for text: String, font: PlatformFont) -> CGFloat {
    guard !text.isEmpty else { return 0 }
    let rect = attributedString(text, font: font).boundingRect(
      with: CGSize(width: .greatestFiniteMagnitude, height: font.lineHeight),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      context: nil
    )
    return ceil(rect.width)
  }

  private static func attributedString(_ text: String, font: PlatformFont) -> NSAttributedString {
    NSAttributedString(
      string: text,
      attributes: [.font: font]
    )
  }

  private static func swiftUIFont(size: CGFloat, weight: Font.Weight) -> Font {
    Font.system(size: size, weight: weight, design: .rounded)
  }

  private static func platformFont(size: CGFloat, weight: Font.Weight) -> PlatformFont {
#if os(macOS)
    return NSFont.systemFont(ofSize: size, weight: convertWeight(weight))
#else
    return UIFont.systemFont(ofSize: size, weight: convertWeight(weight))
#endif
  }

#if os(macOS)
  private static func convertWeight(_ weight: Font.Weight) -> NSFont.Weight {
    switch weight {
    case .ultraLight: return .ultraLight
    case .thin: return .thin
    case .light: return .light
    case .regular: return .regular
    case .medium: return .medium
    case .semibold: return .semibold
    case .bold: return .bold
    case .heavy: return .heavy
    case .black: return .black
    default: return .regular
    }
  }
#else
  private static func convertWeight(_ weight: Font.Weight) -> UIFont.Weight {
    switch weight {
    case .ultraLight: return .ultraLight
    case .thin: return .thin
    case .light: return .light
    case .regular: return .regular
    case .medium: return .medium
    case .semibold: return .semibold
    case .bold: return .bold
    case .heavy: return .heavy
    case .black: return .black
    default: return .regular
    }
  }
#endif
}

#Preview {
    let container = SwiftLEGOModelContainer.preview
    let context = ModelContext(container)
    let fetch = FetchDescriptor<BrickSet>()
    let brickSet = try! context.fetch(fetch).first!

    return SetLabelPreviewView(brickSet: brickSet)
        .modelContainer(container)
}

private struct BagSelectionView: View {
    @Binding var bagCount: Int

    private let maxBagCount: Int = 50

    var body: some View {
        Stepper(value: $bagCount, in: 1...maxBagCount) {
            Text("Total bags: \(bagCount)")
        }
    }
}
#if os(macOS)
struct LabelPrintSheet: View {
    @Environment(\.dismiss) private var dismiss
    let brickSet: BrickSet
    @State private var isPrinting = false
    @State private var bagCount: Int = 1
    private let labelSize: CGSize

    init(brickSet: BrickSet) {
        self.brickSet = brickSet
        self.labelSize = LabelMetrics.labelSize(for: brickSet)
    }

    private var bagNumbers: [Int] {
        guard bagCount > 0 else { return [1] }
        return Array(1...bagCount)
    }

    private var previewBagIndex: Int? {
        bagCount > 1 ? 1 : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Label Preview")
                    .font(.title2.weight(.semibold))
                Text("\(brickSet.setNumber) • \(brickSet.name)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            SetLabelPreviewView(
                brickSet: brickSet,
                labelSize: labelSize,
                displayScale: LabelMetrics.previewScale,
                bagIndex: previewBagIndex,
                bagCount: bagCount
            )
                .frame(maxWidth: .infinity)
                .background(Color.clear)

            BagSelectionView(bagCount: $bagCount)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    printLabel()
                } label: {
                    if isPrinting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Print", systemImage: "printer")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isPrinting)
            }
        }
        .padding(28)
        .frame(minWidth: 420, minHeight: 360)
    }

    private func printLabel() {
        guard !isPrinting else { return }
        guard let operation = makePrintOperation() else { return }

        isPrinting = true
        defer { isPrinting = false }

        if operation.run() {
            dismiss()
        }
    }

    private func makePrintOperation() -> NSPrintOperation? {
        let printInfo = NSPrintInfo()
        configurePrintInfo(printInfo, desiredSize: labelSize)

        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let renderingView = LabelPrintPagingView(
            brickSet: brickSet,
            labelSize: labelSize,
            bagNumbers: bagNumbers,
            bagCount: bagCount,
            scale: scale
        )

        let operation = NSPrintOperation(view: renderingView, printInfo: printInfo)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = false
        operation.showsPreview = true
        operation.printPanel.options = [.showsOrientation]
        return operation
    }
}

private final class LabelPrintPagingView: NSView {
    private let labelSize: CGSize
    private let labelImages: [NSImage]

    init(
        brickSet: BrickSet,
        labelSize: CGSize,
        bagNumbers: [Int],
        bagCount: Int,
        scale: CGFloat
    ) {
        let resolvedBags = bagNumbers.isEmpty ? [1] : bagNumbers
        self.labelSize = labelSize
        self.labelImages = resolvedBags.map { bagNumber in
            let renderer = ImageRenderer(content:
                SetLabelCanvas(brickSet: brickSet, bagIndex: bagNumber, bagCount: bagCount)
                    .frame(width: labelSize.width, height: labelSize.height)
            )
            renderer.scale = scale
            return renderer.nsImage ?? NSImage(size: NSSize(width: labelSize.width, height: labelSize.height))
        }
        let totalHeight = labelSize.height * CGFloat(self.labelImages.count)
        super.init(frame: NSRect(x: 0, y: 0, width: labelSize.width, height: totalHeight))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }

    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        let pages = max(1, labelImages.count)
        range.pointee = NSRange(location: 1, length: pages)
        return true
    }

    override func rectForPage(_ page: Int) -> NSRect {
        let originY = CGFloat(page - 1) * labelSize.height
        return NSRect(x: 0, y: originY, width: labelSize.width, height: labelSize.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        for (index, image) in labelImages.enumerated() {
            let pageRect = rectForPage(index + 1)
            if dirtyRect.intersects(pageRect) {
                image.draw(in: pageRect)
            }
        }
    }
}

private func configurePrintInfo(_ printInfo: NSPrintInfo, desiredSize: CGSize) {
    let size = NSSize(width: desiredSize.width, height: desiredSize.height)

    let selection = resolvePaperSelection(for: printInfo.printer ?? NSPrintInfo.shared.printer, desired: size)

    printInfo.paperSize = selection.size
    printInfo.dictionary[.paperSize] = NSValue(size: selection.size)
    printInfo.orientation = .portrait
    if let name = selection.paperName {
        printInfo.paperName = name
        printInfo.dictionary[.paperName] = name.rawValue
    } else {
        printInfo.paperName = NSPrintInfo.PaperName("SwiftLEGO.Custom.62x38")
        printInfo.dictionary[.paperName] = "SwiftLEGO.Custom.62x38"
    }

    printInfo.leftMargin = 0
    printInfo.rightMargin = 0
    printInfo.topMargin = 0
    printInfo.bottomMargin = 0
    printInfo.scalingFactor = 1.0
    printInfo.isVerticallyCentered = false
    printInfo.isHorizontallyCentered = false
    printInfo.horizontalPagination = .clip
    printInfo.verticalPagination = .clip
}

private struct PaperSelection {
    let paperName: NSPrintInfo.PaperName?
    let size: NSSize
    let orientation: NSPrintInfo.PaperOrientation
    let widthDelta: CGFloat
    let heightDelta: CGFloat
}

private func resolvePaperSelection(for printer: NSPrinter?, desired: NSSize) -> PaperSelection {
    let custom = PaperSelection(
        paperName: nil,
        size: desired,
        orientation: .portrait,
        widthDelta: 0,
        heightDelta: 0
    )

    guard let printer else { return custom }

    let matches: [PaperSelection] = printer.paperNames.compactMap { name in
        let candidate = printer.pageSize(forPaper: name)
        guard candidate.width > 0, candidate.height > 0 else { return nil }

        let portrait = PaperSelection(
            paperName: name,
            size: candidate,
            orientation: .portrait,
            widthDelta: abs(candidate.width - desired.width),
            heightDelta: abs(candidate.height - desired.height)
        )

        let swappedSize = NSSize(width: candidate.height, height: candidate.width)
        let landscape = PaperSelection(
            paperName: name,
            size: swappedSize,
            orientation: .landscape,
            widthDelta: abs(swappedSize.width - desired.width),
            heightDelta: abs(swappedSize.height - desired.height)
        )

        return portrait.widthDelta <= landscape.widthDelta ? portrait : landscape
    }

    #if DEBUG
    PrintDiagnostics.log(printer: printer, desired: desired, matches: matches)
    #endif

    guard !matches.isEmpty else { return custom }

    let tolerance: CGFloat = 1.0
    let filtered = matches.filter { $0.widthDelta <= tolerance }
    let ordered = (filtered.isEmpty ? matches : filtered)
        .sorted { lhs, rhs in
            if lhs.widthDelta != rhs.widthDelta {
                return lhs.widthDelta < rhs.widthDelta
            }
            if lhs.heightDelta != rhs.heightDelta {
                return lhs.heightDelta < rhs.heightDelta
            }
            if lhs.orientation != rhs.orientation {
                return lhs.orientation == .portrait
            }
            return lhs.size.height < rhs.size.height
        }

    guard let best = ordered.first else { return custom }

    if best.heightDelta > tolerance {
        return custom
    }

    return best
}

#if DEBUG
private enum PrintDiagnostics {
    private static var loggedPrinters: Set<String> = []

    static func log(printer: NSPrinter, desired: NSSize, matches: [PaperSelection]) {
        let identifier = printer.name
        guard !loggedPrinters.contains(identifier) else { return }
        loggedPrinters.insert(identifier)

        print("🖨️ SwiftLEGO Print Diagnostics — Printer: \(identifier)")
        print("  Desired size: \(desired.width, specifier: "%.2f") x \(desired.height, specifier: "%.2f") pt")
        if matches.isEmpty {
            print("  No paper presets reported by printer.")
        } else {
            for match in matches {
                let name = match.paperName?.rawValue ?? "<custom>"
                print("  • \(name): \(match.size.width, specifier: "%.2f") x \(match.size.height, specifier: "%.2f") pt — Δw \(match.widthDelta, specifier: "%.2f"), Δh \(match.heightDelta, specifier: "%.2f")")
            }
        }
    }
}
#endif
#else
@available(iOS 16.0, *)
struct LabelPrintSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    let brickSet: BrickSet
    @State private var isPrinting = false
    @State private var anchorView: UIView?
    @State private var printDelegate: LabelPrintDelegate
    @State private var bagCount: Int = 1
    private let labelSize: CGSize

    init(brickSet: BrickSet) {
        self.brickSet = brickSet
        let resolvedSize = LabelMetrics.labelSize(for: brickSet)
        self._printDelegate = State(initialValue: LabelPrintDelegate(labelSize: resolvedSize))
        self.labelSize = resolvedSize
    }

    private var bagNumbers: [Int] {
        guard bagCount > 0 else { return [1] }
        return Array(1...bagCount)
    }

    private var previewBagIndex: Int? {
        bagCount > 1 ? 1 : nil
    }

    var body: some View {
        NavigationStack {
            VStack {
                Spacer(minLength: 12)

                SetLabelPreviewView(
                    brickSet: brickSet,
                    labelSize: labelSize,
                    displayScale: LabelMetrics.previewScale,
                    bagIndex: previewBagIndex,
                    bagCount: bagCount
                )
                    .frame(maxWidth: .infinity, alignment: .center)

                BagSelectionView(bagCount: $bagCount)
                    .padding(.horizontal)

                Spacer(minLength: 24)

                PrintAnchorView(anchorView: $anchorView)
                    .frame(width: 0, height: 0)

                Spacer(minLength: 12)
            }
            .padding(.horizontal)
            .navigationTitle("Print Label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isPrinting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button {
                            printLabel()
                        } label: {
                            Label("Print", systemImage: "printer")
                        }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                        .tint(.accentColor)
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func printLabel() {
        guard !isPrinting else { return }
        let resolvedScale = anchorView?.window?.windowScene?.screen.scale ??
            anchorView?.window?.screen.scale ??
            anchorView?.traitCollection.displayScale ??
            displayScale

        let controller = UIPrintInteractionController.shared
        controller.printInfo = UIPrintInfo(dictionary: nil)
        controller.printInfo?.outputType = .general
        controller.printInfo?.jobName = "\(brickSet.setNumber) Label"
        controller.printInfo?.orientation = .portrait
        controller.printPageRenderer = LabelPrintPageRenderer(
            brickSet: brickSet,
            labelSize: labelSize,
            displayScale: resolvedScale,
            bagNumbers: bagNumbers,
            bagCount: bagCount
        )
        controller.delegate = printDelegate
        printDelegate.labelSize = labelSize

        isPrinting = true
        let completion: UIPrintInteractionController.CompletionHandler = { _, completed, error in
            isPrinting = false
            if completed && error == nil {
                dismiss()
            }
        }

        if let anchorView,
           [.pad, .mac].contains(UIDevice.current.userInterfaceIdiom) {
            let targetRect: CGRect
            if anchorView.bounds.isEmpty {
                targetRect = CGRect(x: 0, y: 0, width: 1, height: 1)
            } else {
                targetRect = anchorView.bounds
            }
            controller.present(from: targetRect, in: anchorView, animated: true, completionHandler: completion)
        } else {
            controller.present(animated: true, completionHandler: completion)
        }
    }
}

@available(iOS 16.0, *)
@MainActor
private final class LabelPrintPageRenderer: UIPrintPageRenderer {
    private let brickSet: BrickSet
    private let labelSize: CGSize
    private let displayScale: CGFloat
    private let bagNumbers: [Int]
    private let bagCount: Int

    init(brickSet: BrickSet, labelSize: CGSize, displayScale: CGFloat, bagNumbers: [Int], bagCount: Int) {
        self.brickSet = brickSet
        self.labelSize = labelSize
        self.displayScale = displayScale
        self.bagNumbers = bagNumbers
        self.bagCount = bagCount
        super.init()
    }

    override var numberOfPages: Int { max(1, bagNumbers.count) }

    override var paperRect: CGRect {
        CGRect(origin: .zero, size: labelSize)
    }

    override var printableRect: CGRect {
        paperRect.insetBy(dx: 0, dy: 0)
    }

    override func drawPage(at pageIndex: Int, in printableRect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        let bagIndex = bagNumbers.indices.contains(pageIndex) ? bagNumbers[pageIndex] : nil
        context.saveGState()
        let renderer = ImageRenderer(content:
            SetLabelCanvas(brickSet: brickSet, bagIndex: bagIndex, bagCount: bagCount)
                .frame(width: labelSize.width, height: labelSize.height)
        )
        renderer.scale = displayScale
        if let image = renderer.uiImage {
            image.draw(in: printableRect)
        }
        context.restoreGState()
    }
}

@available(iOS 16.0, *)
private final class LabelPrintDelegate: NSObject, UIPrintInteractionControllerDelegate {
    var labelSize: CGSize

    init(labelSize: CGSize) {
        self.labelSize = labelSize
    }

    func printInteractionController(_ printInteractionController: UIPrintInteractionController, choosePaper paperList: [UIPrintPaper]) -> UIPrintPaper {
        UIPrintPaper.bestPaper(forPageSize: labelSize, withPapersFrom: paperList)
    }

    @available(iOS 17.0, *)
    func printInteractionController(_ printInteractionController: UIPrintInteractionController, cutLengthFor paper: UIPrintPaper) -> CGFloat {
        let targetLength = labelSize.height
        return min(targetLength, paper.paperSize.height)
    }
}

@available(iOS 16.0, *)
private struct PrintAnchorView: UIViewRepresentable {
    @Binding var anchorView: UIView?

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        DispatchQueue.main.async {
            anchorView = view
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
#endif
