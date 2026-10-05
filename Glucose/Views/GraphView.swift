import SwiftUI
import Charts
import Observation

/// Hover state kept in a reference box rather than in `@State` on `GraphView`.
///
/// SwiftUI attributes an `@Observable` read to whichever body actually reads
/// it, so keeping the cursor position here means a mouse move invalidates only
/// the small `HoverIndicator` below the plot — not `GraphView.body`, which
/// would rebuild every mark and re-spline the catmullRom curve on each frame.
@Observable
final class ChartHoverState {
    var reading: GlucoseReading?
}

struct GraphView: View {
    let readings: [GlucoseReading]
    let range: TimeRange
    let hover: ChartHoverState

    private var domain: ClosedRange<Date> {
        let now = Date()
        return now.addingTimeInterval(-Double(range.minutes) * 60)...now
    }

    private var yDomain: ClosedRange<Double> {
        let mmols = readings.map(\.mmol)
        let dataMin = mmols.min() ?? GlucoseRange.lowMmol
        let dataMax = mmols.max() ?? GlucoseRange.highMmol
        let low = min(GlucoseRange.lowMmol, dataMin - 0.3)
        let high = max(GlucoseRange.highMmol, dataMax + 0.3)
        return low...high
    }

    private var hasHypoReading: Bool {
        readings.contains { $0.mmol < GlucoseRange.lowMmol }
    }

    private var hasHyperReading: Bool {
        readings.contains { $0.mmol > GlucoseRange.highMmol }
    }

    private var yAxisValues: [Double] {
        // 3.9 and 10.0 are the boundary marks; 5.5 and 8.3 are the
        // 100 mg/dL and 150 mg/dL intermediate marks that traditionally
        // appear on CGM graphs.
        var values: [Double] = [GlucoseRange.lowMmol, 5.5, 8.3, GlucoseRange.highMmol]
        if hasHypoReading {
            values.append(yDomain.lowerBound)
        }
        if hasHyperReading {
            values.append(yDomain.upperBound)
        }
        return values.sorted()
    }

    private var showsPerReadingDots: Bool {
        switch range {
        case .h1, .h3: return true
        case .h6, .h12, .h24: return false
        }
    }

    // Solid hairlines in the system separator colour, matching the dividers in
    // the native menu-bar dropdowns.
    private static let gridStroke = StrokeStyle(lineWidth: 1)
    private static let gridColor = Color(nsColor: .separatorColor)

    var body: some View {
        Chart {
            // Hypo band (low, dark red) — only when a reading falls below.
            if hasHypoReading {
                RectangleMark(
                    xStart: .value("start", domain.lowerBound),
                    xEnd: .value("end", domain.upperBound),
                    yStart: .value("hypo low", yDomain.lowerBound),
                    yEnd: .value("hypo high", GlucoseRange.lowMmol)
                )
                .foregroundStyle(Color.red.opacity(0.18))
            }

            // Hyper band (high, dark blue) — only when a reading goes above.
            if hasHyperReading {
                RectangleMark(
                    xStart: .value("start", domain.lowerBound),
                    xEnd: .value("end", domain.upperBound),
                    yStart: .value("hyper low", GlucoseRange.highMmol),
                    yEnd: .value("hyper high", yDomain.upperBound)
                )
                .foregroundStyle(Color.yellow.opacity(0.22))
            }

            // Trend line
            ForEach(readings) { reading in
                LineMark(
                    x: .value("time", reading.date),
                    y: .value("mmol", reading.mmol)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.green)
                .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            }

            // Per-reading dots for short ranges where density stays readable.
            if showsPerReadingDots {
                ForEach(readings) { reading in
                    PointMark(
                        x: .value("time", reading.date),
                        y: .value("mmol", reading.mmol)
                    )
                    .symbolSize(28)
                    .foregroundStyle(Color.green)
                }
            }

            // NOTE: the hover rule + highlighted dot are intentionally NOT in
            // this builder, and neither is the cursor position they follow.
            // Both live below the plot in `HoverIndicator` so that a cursor
            // move never invalidates this body — re-running it would rebuild
            // all ~288 marks and re-spline the catmullRom line every frame.
        }
        .chartOverlay { proxy in
            HoverIndicator(readings: readings, proxy: proxy, hover: hover)
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(position: .trailing, values: yAxisValues) { value in
                AxisGridLine(stroke: Self.gridStroke)
                    .foregroundStyle(Self.gridColor)
                AxisValueLabel(horizontalSpacing: 6) {
                    if let d = value.as(Double.self) {
                        Text(String(format: "%.1f", d))
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: range.xAxisStrideHours)) { value in
                AxisGridLine(stroke: Self.gridStroke)
                    .foregroundStyle(Self.gridColor)
                AxisValueLabel(anchor: .top, collisionResolution: .disabled) {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }
        }
    }
}

// The chart is expensive to rebuild, so let SwiftUI skip `body` whenever the
// data is unchanged. `hover` is compared by identity only: the indicator keeps
// itself up to date through observation, so a cursor move — which does re-run
// `PopoverView.body` for the stats row — must not drag the chart along with it.
extension GraphView: Equatable {
    static func == (lhs: GraphView, rhs: GraphView) -> Bool {
        lhs.range == rhs.range
            && lhs.hover === rhs.hover
            && lhs.readings == rhs.readings
    }
}

/// The hover rule + highlighted dot, plus the hit testing that drives them.
///
/// This sits inside `.chartOverlay`, below the plot in the view tree, so that
/// redrawing it costs two shapes and touches none of the chart's data marks.
/// It also owns hit testing: `chartXSelection` would need its binding declared
/// above the `Chart`, which is exactly what used to force a full rebuild.
private struct HoverIndicator: View {
    let readings: [GlucoseReading]
    let proxy: ChartProxy
    let hover: ChartHoverState

    var body: some View {
        GeometryReader { geo in
            let plot = proxy.plotFrame.map { geo[$0] }
            ZStack(alignment: .topLeading) {
                Color.clear
                if let plot {
                    marks(in: plot)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard let plot, case .active(let point) = phase, plot.contains(point) else {
                    focus(on: nil)
                    return
                }
                let date = proxy.value(atX: point.x - plot.minX, as: Date.self)
                focus(on: date.flatMap(nearestReading(to:)))
            }
        }
    }

    @ViewBuilder
    private func marks(in plot: CGRect) -> some View {
        let active = hover.reading
        // Highlighted reading: hovered, or fall back to latest.
        if let target = active ?? readings.last,
           let x = proxy.position(forX: target.date),
           let y = proxy.position(forY: target.mmol) {
            // Vertical rule only while actively hovering.
            if active != nil {
                Rectangle()
                    .fill(Color.primary.opacity(0.85))
                    .frame(width: 1, height: plot.height)
                    .position(x: plot.minX + x, y: plot.midY)
            }
            Circle()
                .fill(Color.primary)
                .frame(width: 10, height: 10)
                .position(x: plot.minX + x, y: plot.minY + y)
        }
    }

    // Writing an unchanged value would still fire observation, redrawing the
    // indicator for every pixel of travel within one reading's slot.
    private func focus(on reading: GlucoseReading?) {
        if hover.reading != reading {
            hover.reading = reading
        }
    }

    private func nearestReading(to date: Date) -> GlucoseReading? {
        readings.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(date)) < abs(rhs.date.timeIntervalSince(date))
        }
    }
}
