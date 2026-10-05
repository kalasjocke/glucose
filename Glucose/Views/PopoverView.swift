import SwiftUI
import AppKit

struct PopoverView: View {
    @Environment(GlucoseStore.self) private var store
    @State private var range: TimeRange = .h24
    // A reference box rather than a plain `@State` value: a cursor move must
    // invalidate this view (the stats row follows the hover) without pushing a
    // fresh, unequal `GraphView` down and forcing the chart to rebuild.
    @State private var hover = ChartHoverState()
    @Namespace private var rangeSelection

    private var filtered: [GlucoseReading] { store.readings(in: range) }
    private var displayReading: GlucoseReading? { hover.reading ?? store.latestReading }

    var body: some View {
        VStack(spacing: 6) {
            if !store.hasCredentials {
                emptyState
            } else {
                rangePicker
                statsRow
                GraphView(readings: filtered, range: range, hover: hover)
                    .equatable()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(10)
        .frame(width: 360, height: 280)
        .onChange(of: range) { _, _ in hover.reading = nil }
    }

    // Styled after the Stocks app's range picker: plain labels spread across
    // the width, with a soft capsule behind the selected one. Quieter on the
    // glass than a bordered segmented control.
    private var rangePicker: some View {
        HStack(spacing: 0) {
            ForEach(TimeRange.allCases) { r in
                if r != TimeRange.allCases.first {
                    Spacer(minLength: 0)
                }
                rangeButton(r)
            }
        }
        .animation(.snappy(duration: 0.25), value: range)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Time range")
    }

    private func rangeButton(_ r: TimeRange) -> some View {
        let selected = r == range
        return Button {
            range = r
        } label: {
            Text(r.label)
                .font(.subheadline.weight(selected ? .bold : .semibold))
                .foregroundStyle(selected ? Color.primary : Color.primary.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background {
                    if selected {
                        Capsule()
                            .fill(.quaternary)
                            .matchedGeometryEffect(id: "selection", in: rangeSelection)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var statsRow: some View {
        let display = displayReading
        // Treat the *displayed* reading as stale only when we're showing the
        // latest one and the store is stale — hovered points are exact picks.
        let stale = (hover.reading == nil) && store.isStale
        let angle = display.flatMap { store.readings.trendAngleDegrees(endingAt: $0) }
        return ZStack {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                trendArrow(angle: angle, fallback: display?.trend)
                    .imageScale(.medium)
                Text(display.map { String(format: "%.1f", $0.mmol) } ?? "—")
                Text("mmol/L")
                    .font(.title3.weight(.regular))
                    .foregroundStyle((stale ? Color.gray : Color.green).opacity(0.85))
            }
            .font(.title.weight(.semibold))
            .foregroundStyle(stale ? .gray : .green)

            HStack(alignment: .firstTextBaseline) {
                Text(diffLabel(for: display) ?? "—")
                    .font(.callout.italic())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(timeLabel(for: display?.date))
                    .font(.callout.italic())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 2)
    }

    // Relative ("2m", "45m") for recent readings, absolute HH:mm once a
    // reading is more than an hour old — vague "2h" labels aren't useful then.
    private func timeLabel(for date: Date?) -> String {
        guard let date else { return "—" }
        if Date().timeIntervalSince(date) > 3600 {
            return date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        }
        return date.timeAgoCompact
    }

    private func diffLabel(for reading: GlucoseReading?) -> String? {
        guard let reading,
              let idx = store.readings.firstIndex(where: { $0.id == reading.id }),
              idx >= 1 else { return nil }
        let delta = reading.mmol - store.readings[idx - 1].mmol
        return String(format: "%+.1f mmol/L", delta)
    }

    @ViewBuilder
    private func trendArrow(angle: Double?, fallback: TrendDirection?) -> some View {
        if let angle {
            Image(systemName: "arrow.right")
                .rotationEffect(.degrees(angle))
                .animation(.easeInOut(duration: 0.3), value: angle)
        } else if let fallback {
            Image(systemName: fallback.sfSymbol)
        } else {
            Image(systemName: "circle")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "drop.degreesign")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("Sign in to Dexcom Share")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("Right-click the menu bar value and choose Settings to enter credentials.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Button("Open Settings…") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension Date {
    var timeAgoCompact: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
