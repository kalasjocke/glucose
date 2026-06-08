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

            // Highlighted reading (hovered, or fall back to latest).
            if let focus = hovered ?? readings.last {
                PointMark(
                    x: .value("time", focus.date),
                    y: .value("mmol", focus.mmol)
                )
                .symbolSize(80)
                .foregroundStyle(Color.white)
            }

            // Vertical rule only while hovering.
            if let hovered {
                RuleMark(x: .value("hover", hovered.date))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
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
