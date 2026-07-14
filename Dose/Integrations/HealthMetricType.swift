import Foundation
import HealthKit

/// The bridge between a user-facing `TrackedMetric` and a HealthKit sample type. A small fixed set of
/// well-known vitals, matched by the metric's NAME — so we never need a per-metric config field (or a
/// schema migration). Only the store interaction is device-only; the mapping/conversion below is pure.
enum HealthMetricType: String, CaseIterable {
    case weight, heartRate, glucose, oxygenSaturation, bodyTemperature

    var quantityTypeID: HKQuantityTypeIdentifier {
        switch self {
        case .weight: .bodyMass
        case .heartRate: .heartRate
        case .glucose: .bloodGlucose
        case .oxygenSaturation: .oxygenSaturation
        case .bodyTemperature: .bodyTemperature
        }
    }
    var quantityType: HKQuantityType? { HKQuantityType.quantityType(forIdentifier: quantityTypeID) }

    /// The HealthKit unit we read/write in — matched to `displayUnit`.
    var hkUnit: HKUnit {
        switch self {
        case .weight: .gramUnit(with: .kilo)
        case .heartRate: HKUnit.count().unitDivided(by: .minute())
        case .glucose: HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))  // mg/dL
        case .oxygenSaturation: .percent()
        case .bodyTemperature: .degreeCelsius()
        }
    }
    var displayUnit: String {
        switch self {
        case .weight: "kg"
        case .heartRate: "bpm"
        case .glucose: "mg/dL"
        case .oxygenSaturation: "%"
        case .bodyTemperature: "°C"
        }
    }

    /// Match a tracked metric to a HealthKit type by name (case-insensitive). `nil` = not HK-backed.
    static func forMetricName(_ name: String) -> HealthMetricType? {
        switch name.lowercased().trimmingCharacters(in: .whitespaces) {
        case "weight", "body weight": return .weight
        case "heart rate", "pulse", "heartrate": return .heartRate
        case "glucose", "blood glucose", "blood sugar": return .glucose
        case "oxygen", "oxygen saturation", "spo2", "blood oxygen": return .oxygenSaturation
        case "temperature", "body temperature": return .bodyTemperature
        default: return nil
        }
    }

    /// Convert a HealthKit quantity value (read in `hkUnit`) to the app's stored `Double`. HealthKit stores
    /// oxygen saturation as a fraction (0…1 in percent unit), so scale it to 0…100 for display.
    func appValue(fromHKValue hkValue: Double) -> Double {
        self == .oxygenSaturation ? hkValue * 100 : hkValue
    }

    /// The reverse: the app's `Double` → a HealthKit quantity value in `hkUnit`.
    func hkValue(fromAppValue appValue: Double) -> Double {
        self == .oxygenSaturation ? appValue / 100 : appValue
    }
}
