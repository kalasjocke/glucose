import SwiftUI
import Charts

struct GraphView: View {
    let readings: [GlucoseReading]
    let range: TimeRange
    @Binding var hovered: GlucoseReading?

    @State private var hoverDate: Date?

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

    private func nearestReading(to date: Date) -> GlucoseReading? {
        readings.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(date)) < abs(rhs.date.timeIntervalSince(date))
        }
    }

    // Lightweight overlay for the hover rule + highlighted dot. Re-rendering
    // this on every cursor move is cheap because it only draws two shapes and
    // never touches the chart's data marks.
    @ViewBuilder
    private func hoverOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geo in
            if let plotAnchor = proxy.plotFrame {
                let plot = geo[plotAnchor]
                // Drive the dot from `hoverDate` directly — it updates in the
                // same frame as the cursor, whereas `hovered` lags one frame
                // (it's set via onChange), which made the dot flash at the
                // latest reading before snapping to the cursor.
                let active = hoverDate.flatMap(nearestReading(to:))
                // Highlighted reading: hovered, or fall back to latest.
                if let focus = active ?? readings.last,
                   let x = proxy.position(forX: focus.date),
                   let y = proxy.position(forY: focus.mmol) {
                    // Vertical rule only while actively hovering.
                    if active != nil {
                        Rectangle()
                            .fill(Color.white.opacity(0.85))
                            .frame(width: 1, height: plot.height)
                            .position(x: plot.minX + x, y: plot.midY)
                    }
                    Circle()
                        .fill(Color.white)
                        .frame(width: 10, height: 10)
                        .position(x: plot.minX + x, y: plot.minY + y)
                }
            }
        }
        // The overlay must never intercept pointer events, or it steals them
        // from chartXSelection — making the selection flicker to nil and the
        // dot bounce back to the latest reading.
        .allowsHitTesting(false)
    }

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
            // this builder. Drawing them here would make the whole chart
            // (including the expensive catmullRom line) depend on `hovered`,
            // forcing a full re-spline/re-layout on every cursor move. They
            // live in `.chartOverlay` below so hover stays cheap.
        }
        .chartOverlay { proxy in
            hoverOverlay(proxy: proxy)
        }
        .chartXSelection(value: $hoverDate)
        .onChange(of: hoverDate) { _, newValue in
            hovered = newValue.flatMap(nearestReading(to:))
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(position: .trailing, values: yAxisValues) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    .foregroundStyle(.white.opacity(0.25))
                AxisValueLabel(horizontalSpacing: 6) {
                    if let d = value.as(Double.self) {
                        Text(String(format: "%.1f", d))
                            .foregroundStyle(.white.opacity(0.75))
                            .font(.caption)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: range.xAxisStrideHours)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    .foregroundStyle(.white.opacity(0.18))
                AxisValueLabel(anchor: .top, collisionResolution: .disabled) {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                            .foregroundStyle(.white.opacity(0.75))
                            .font(.caption)
                    }
                }
            }
        }
        .chartPlotStyle { plot in
            plot.background(Color.black.opacity(0.35))
        }
    }
}
