import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct SetLabelPreviewView: View {
    let brickSet: BrickSet
    var labelSize: CGSize = LabelMetrics.printSize
    var displayScale: CGFloat = LabelMetrics.previewScale

    var body: some View {
        ScaledLabelCanvas(
            brickSet: brickSet,
            labelSize: labelSize,
            scale: displayScale
        )
        .padding()
        .background(.white)
    }
}

private struct SetLabelCanvas: View {
    let brickSet: BrickSet

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
    }
}

private struct ScaledLabelCanvas: View {
    let brickSet: BrickSet
    let labelSize: CGSize
    let scale: CGFloat

    var body: some View {
        let canvas = SetLabelCanvas(brickSet: brickSet)
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
    static let labelHeightMillimeters: CGFloat = 20

    static let printSize = CGSize(
        width: points(fromMillimeters: labelWidthMillimeters),
        height: points(fromMillimeters: labelHeightMillimeters)
    )
    static let previewScale: CGFloat = 2.0
    static let uncategorizedTitle = "Uncategorized"

    static let horizontalPadding: CGFloat = 6
    static let verticalPadding: CGFloat = 6
    static let verticalSpacing: CGFloat = 4

    static let identifierFont = Font.system(size: 14, weight: .bold, design: .rounded)
    static let identifierMinimumScale: CGFloat = 0.75

    static let titleFont = Font.system(size: 16, weight: .regular, design: .rounded)
    static let titleSingleLineMinimumScale: CGFloat = 0.8

    static let titleMultiLineFont = Font.system(size: 14, weight: .regular, design: .rounded)
    static let titleMultiLineMinimumScale: CGFloat = 0.75

    static func points(fromMillimeters millimeters: CGFloat) -> CGFloat {
        millimeters * 72.0 / 25.4
    }
}

#Preview {
    let container = SwiftLEGOModelContainer.preview
    let context = ModelContext(container)
    let fetch = FetchDescriptor<BrickSet>()
    let brickSet = try! context.fetch(fetch).first!

    return SetLabelPreviewView(brickSet: brickSet)
        .modelContainer(container)
}
#if os(macOS)
struct LabelPrintSheet: View {
    @Environment(\.dismiss) private var dismiss
    let brickSet: BrickSet
    @State private var isPrinting = false

    private var labelSize: CGSize {
        LabelMetrics.printSize
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
                displayScale: LabelMetrics.previewScale
            )
                .frame(maxWidth: .infinity)
                .background(Color.clear)

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

        let operation = NSPrintOperation(view: AppKitLabelRenderingView(brickSet: brickSet, labelSize: labelSize), printInfo: printInfo)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = false
        operation.showsPreview = true
        operation.printPanel.options = [.showsOrientation]
        return operation
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
    let brickSet: BrickSet
    @State private var isPrinting = false
    @State private var anchorView: UIView?
    @State private var printDelegate = LabelPrintDelegate(labelSize: LabelMetrics.printSize)

    private var labelSize: CGSize {
        LabelMetrics.printSize
    }

    var body: some View {
        NavigationStack {
            VStack {
                Spacer(minLength: 12)

                SetLabelPreviewView(
                    brickSet: brickSet,
                    labelSize: labelSize,
                    displayScale: LabelMetrics.previewScale
                )
                    .frame(maxWidth: .infinity, alignment: .center)

                Spacer(minLength: 24)

                Button {
                    printLabel()
                } label: {
                    if isPrinting {
                        ProgressView()
                            .controlSize(.large)
                    } else {
                        Label("Print", systemImage: "printer")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPrinting)

                PrintAnchorView(anchorView: $anchorView)
                    .frame(width: 0, height: 0)

                Spacer(minLength: 12)
            }
            .padding(.horizontal)
            .navigationTitle("Print Label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func printLabel() {
        guard !isPrinting else { return }
        let controller = UIPrintInteractionController.shared
        controller.printInfo = UIPrintInfo(dictionary: nil)
        controller.printInfo?.outputType = .general
        controller.printInfo?.jobName = "\(brickSet.setNumber) Label"
        controller.printInfo?.orientation = .portrait
        controller.printPageRenderer = LabelPrintPageRenderer(brickSet: brickSet, labelSize: labelSize)
        controller.delegate = printDelegate

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

    init(brickSet: BrickSet, labelSize: CGSize) {
        self.brickSet = brickSet
        self.labelSize = labelSize
        super.init()
    }

    override var numberOfPages: Int { 1 }

    override var paperRect: CGRect {
        CGRect(origin: .zero, size: labelSize)
    }

    override var printableRect: CGRect {
        paperRect.insetBy(dx: 0, dy: 0)
    }

    override func drawPage(at pageIndex: Int, in printableRect: CGRect) {
        guard pageIndex == 0 else { return }
        guard let context = UIGraphicsGetCurrentContext() else { return }

        context.saveGState()
        let renderer = ImageRenderer(content:
            SetLabelCanvas(brickSet: brickSet)
                .frame(width: labelSize.width, height: labelSize.height)
        )
        renderer.scale = UIScreen.main.scale
        if let image = renderer.uiImage {
            image.draw(in: printableRect)
        }
        context.restoreGState()
    }
}

@available(iOS 16.0, *)
private final class LabelPrintDelegate: NSObject, UIPrintInteractionControllerDelegate {
    private let labelSize: CGSize

    init(labelSize: CGSize) {
        self.labelSize = labelSize
    }

    func printInteractionController(_ printInteractionController: UIPrintInteractionController, choosePaper paperList: [UIPrintPaper]) -> UIPrintPaper {
        UIPrintPaper.bestPaper(forPageSize: labelSize, withPapersFrom: paperList)
    }

    @available(iOS 17.0, *)
    func printInteractionController(_ printInteractionController: UIPrintInteractionController, cutLengthFor paper: UIPrintPaper) -> CGFloat {
        let printable = paper.printableRect
        let topMargin = printable.origin.y
        let bottomMargin = paper.paperSize.height - printable.maxY
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
