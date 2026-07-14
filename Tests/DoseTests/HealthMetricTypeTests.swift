import XCTest
import HealthKit
@testable import Dose

/// Phase 3 (HealthKit): the pure mapping between a `TrackedMetric` and a HealthKit type. The store
/// interaction is device-only; this covers everything that isn't.
final class HealthMetricTypeTests: XCTestCase {
    func testNameMappingIsCaseInsensitiveAndCoversPresets() {
        XCTAssertEqual(HealthMetricType.forMetricName("Weight"), .weight)
        XCTAssertEqual(HealthMetricType.forMetricName("weight"), .weight)
        XCTAssertEqual(HealthMetricType.forMetricName("Heart rate"), .heartRate)
        XCTAssertEqual(HealthMetricType.forMetricName("Glucose"), .glucose)
        XCTAssertEqual(HealthMetricType.forMetricName("Oxygen"), .oxygenSaturation)
        XCTAssertEqual(HealthMetricType.forMetricName("SpO2"), .oxygenSaturation)
        XCTAssertNil(HealthMetricType.forMetricName("Pain"))
        XCTAssertNil(HealthMetricType.forMetricName("Custom thing"))
    }

    func testOxygenScalesBetweenFractionAndPercent() {
        let o = HealthMetricType.oxygenSaturation
        XCTAssertEqual(o.appValue(fromHKValue: 0.98), 98, accuracy: 0.001)   // HK fraction → percent for display
        XCTAssertEqual(o.hkValue(fromAppValue: 98), 0.98, accuracy: 0.001)   // percent → HK fraction for storage
    }

    func testNonOxygenValuesPassThroughUnchanged() {
        for type in [HealthMetricType.weight, .heartRate, .glucose, .bodyTemperature] {
            XCTAssertEqual(type.appValue(fromHKValue: 72.5), 72.5)
            XCTAssertEqual(type.hkValue(fromAppValue: 72.5), 72.5)
        }
    }

    func testDisplayUnitsMatchPresets() {
        XCTAssertEqual(HealthMetricType.weight.displayUnit, "kg")
        XCTAssertEqual(HealthMetricType.heartRate.displayUnit, "bpm")
        XCTAssertEqual(HealthMetricType.glucose.displayUnit, "mg/dL")
        XCTAssertEqual(HealthMetricType.oxygenSaturation.displayUnit, "%")
    }

    func testEveryTypeResolvesAHealthKitQuantityType() {
        for type in HealthMetricType.allCases {
            XCTAssertNotNil(type.quantityType, "\(type) resolves a HKQuantityType")
        }
    }
}
