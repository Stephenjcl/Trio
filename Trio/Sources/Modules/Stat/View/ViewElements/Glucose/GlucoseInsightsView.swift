import CoreData
import SwiftUI

/// A read-only "Insights" card that surfaces descriptive trends derived from the
/// user's own recent glucose data.
///
/// This view is intentionally informational only: it describes patterns (trends,
/// time-of-day tendencies, variability) and does NOT make any therapy or dosing
/// recommendations. All computation happens on-device from already-loaded data.
struct GlucoseInsightsView: View {
    /// The unit of measurement for blood glucose values (e.g., mg/dL or mmol/L).
    let units: GlucoseUnits
    /// The lower glucose threshold (mg/dL) used for time-in-range.
    let lowLimit: Decimal
    /// The upper glucose threshold (mg/dL) used for time-in-range.
    let highLimit: Decimal
    /// A list of stored glucose readings (typically the trailing ~90 days).
    let glucose: [GlucoseStored]

    /// Aggregated statistics for a single time window.
    private struct WindowStats {
        let count: Int
        let average: Double // mg/dL
        let timeInRange: Double // percent
    }

    /// The full set of computed insights for the card.
    private struct Insights {
        let recent: WindowStats?
        let previous: WindowStats?
        let cv: Double
        let peakHour: Int?
        let troughHour: Int?
    }

    var body: some View {
        let insights = computeInsights()

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.accentColor)
                Text("Insights")
                    .font(.headline)
                Spacer()
            }

            if let recent = insights.recent {
                HStack(alignment: .top) {
                    insightTile(
                        title: String(localized: "Avg (7d)"),
                        value: formatGlucose(recent.average),
                        delta: insights.previous.map { glucoseDeltaText(recent.average - $0.average) }
                    )
                    Spacer()
                    insightTile(
                        title: String(localized: "TIR (7d)"),
                        value: percentString(recent.timeInRange, fractionDigits: 0),
                        delta: insights.previous.map { pointsDeltaText(recent.timeInRange - $0.timeInRange) }
                    )
                    Spacer()
                    insightTile(
                        title: String(localized: "CV (14d)"),
                        value: percentString(insights.cv, fractionDigits: 1),
                        delta: nil
                    )
                }

                if (insights.peakHour != nil && insights.troughHour != nil) || insights.cv >= 36 {
                    Divider()
                }

                if let peak = insights.peakHour, let trough = insights.troughHour, peak != trough {
                    insightRow(
                        systemImage: "clock",
                        text: String(
                            localized: "Tends to run highest around \(hourString(peak)) and lowest around \(hourString(trough))."
                        )
                    )
                }

                if insights.cv >= 36 {
                    insightRow(
                        systemImage: "waveform.path.ecg",
                        text: String(
                            localized: "Glucose variability is high (CV ≥ 36%), which is associated with more frequent lows and highs."
                        )
                    )
                }

                Text(
                    "Descriptive trends from your recent data — not medical advice. Discuss any therapy changes with your care team."
                )
                .font(.caption2)
                .foregroundStyle(Color.secondary)
            } else {
                Text("Not enough recent glucose data to show insights yet.")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Subviews

    private func insightTile(title: String, value: String, delta: String?) -> some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
            Text(value)
            if let delta = delta {
                Text(delta)
                    .font(.caption2)
                    .foregroundStyle(Color.secondary)
            }
        }
    }

    private func insightRow(systemImage: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.secondary)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Color.secondary)
        }
    }

    // MARK: - Formatting

    private func formatGlucose(_ mgdl: Double) -> String {
        let display = mgdl.asUnit(units)
        return display.formatted(
            .number.grouping(.never).rounded().precision(.fractionLength(units == .mgdL ? 0 : 1))
        )
    }

    private func percentString(_ value: Double, fractionDigits: Int) -> String {
        value.formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits))) + "%"
    }

    private func glucoseDeltaText(_ mgdlDelta: Double) -> String {
        let arrow = mgdlDelta > 0 ? "↑" : (mgdlDelta < 0 ? "↓" : "→")
        let magnitude = abs(mgdlDelta).asUnit(units)
        let formatted = magnitude.formatted(
            .number.grouping(.never).rounded().precision(.fractionLength(units == .mgdL ? 0 : 1))
        )
        return "\(arrow) \(formatted) vs prev"
    }

    private func pointsDeltaText(_ pointsDelta: Double) -> String {
        let arrow = pointsDelta > 0 ? "↑" : (pointsDelta < 0 ? "↓" : "→")
        let formatted = abs(pointsDelta).formatted(.number.grouping(.never).rounded().precision(.fractionLength(0)))
        return "\(arrow) \(formatted) pts vs prev"
    }

    private func hourString(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(.dateTime.hour())
    }

    // MARK: - Computation

    private func computeInsights() -> Insights {
        let now = Date()
        let calendar = Calendar.current
        let recentStart = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let previousStart = calendar.date(byAdding: .day, value: -14, to: now) ?? now

        let recentReadings = glucose.filter { reading in
            guard let date = reading.date else { return false }
            return date >= recentStart && date <= now
        }
        let previousReadings = glucose.filter { reading in
            guard let date = reading.date else { return false }
            return date >= previousStart && date < recentStart
        }
        let last14Readings = glucose.filter { reading in
            guard let date = reading.date else { return false }
            return date >= previousStart && date <= now
        }

        return Insights(
            recent: windowStats(for: recentReadings),
            previous: windowStats(for: previousReadings),
            cv: coefficientOfVariation(for: last14Readings),
            peakHour: hourlyExtreme(for: last14Readings, findMax: true),
            troughHour: hourlyExtreme(for: last14Readings, findMax: false)
        )
    }

    private func windowStats(for readings: [GlucoseStored]) -> WindowStats? {
        let values = readings.map { Int($0.glucose) }
        guard !values.isEmpty else { return nil }

        let average = Double(values.reduce(0, +)) / Double(values.count)
        let low = Double(truncating: lowLimit as NSNumber)
        let high = Double(truncating: highLimit as NSNumber)
        let inRange = values.filter { Double($0) >= low && Double($0) <= high }.count
        let timeInRange = Double(inRange) / Double(values.count) * 100

        return WindowStats(count: values.count, average: average, timeInRange: timeInRange)
    }

    private func coefficientOfVariation(for readings: [GlucoseStored]) -> Double {
        let values = readings.map { Double($0.glucose) }
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        guard mean > 0 else { return 0 }
        let variance = values.reduce(0.0) { $0 + pow($1 - mean, 2) } / Double(values.count - 1)
        return sqrt(variance) / mean * 100
    }

    /// Buckets readings by hour-of-day and returns the hour with the highest (or
    /// lowest) average glucose. Only hours with at least a few readings are
    /// considered so a single outlier can't dominate.
    private func hourlyExtreme(for readings: [GlucoseStored], findMax: Bool) -> Int? {
        let calendar = Calendar.current
        var sums: [Int: (sum: Int, count: Int)] = [:]
        for reading in readings {
            guard let date = reading.date else { continue }
            let hour = calendar.component(.hour, from: date)
            var entry = sums[hour] ?? (sum: 0, count: 0)
            entry.sum += Int(reading.glucose)
            entry.count += 1
            sums[hour] = entry
        }

        let averages = sums.filter { $0.value.count >= 3 }.mapValues { Double($0.sum) / Double($0.count) }
        guard !averages.isEmpty else { return nil }

        return findMax
            ? averages.max(by: { $0.value < $1.value })?.key
            : averages.min(by: { $0.value < $1.value })?.key
    }
}
