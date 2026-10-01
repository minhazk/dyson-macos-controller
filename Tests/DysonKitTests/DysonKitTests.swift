import Foundation
import XCTest
@testable import DysonKit

final class DysonKitTests: XCTestCase {
    func testParsesCurrentStateArraysAndAppliesState() throws {
        let data = Data(#"{"msg":"STATE-CHANGE","product-state":{"fpwr":["OFF","ON"],"fnsp":["0001","0006"],"auto":"ON","hmod":"HEAT","hmax":"02932","oson":"ON","osal":"0090","osau":"0270","fdir":"ON","nmod":"OFF"}}"#.utf8)
        let message = try DysonMessageParser.parse(data)
        var state = DysonState()
        state.apply(message, now: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(state.isOn, true)
        XCTAssertEqual(state.fanSpeed, 6)
        XCTAssertEqual(state.autoMode, true)
        XCTAssertEqual(state.heating, true)
        XCTAssertEqual(state.targetTemperatureCelsius ?? 0, 20.05, accuracy: 0.01)
        XCTAssertEqual(state.oscillationLowAngle, 90)
        XCTAssertEqual(state.oscillationHighAngle, 270)
        XCTAssertEqual(state.frontAirflow, true)
    }

    func testParsesEnvironmentalReadingsAndConvertsTemperature() throws {
        let data = Data(#"{"msg":"ENVIRONMENTAL-CURRENT-SENSOR-DATA","data":{"tact":"2903","hact":"0030","p25r":"0009","pm10":"0005","va10":"0004","noxl":"0011"}}"#.utf8)
        var state = DysonState()
        state.apply(try DysonMessageParser.parse(data))

        XCTAssertEqual(state.roomTemperatureCelsius ?? 0, 17.15, accuracy: 0.01)
        XCTAssertEqual(state.humidity, 30)
        XCTAssertEqual(state.pm25, 9)
        XCTAssertEqual(state.pm10, 5)
        XCTAssertEqual(state.vocIndex, 0.4)
        XCTAssertEqual(state.nitrogenDioxideIndex, 1.1)
    }

    func testEnvironmentalSentinelsRemainUnavailable() throws {
        let data = Data(#"{"msg":"ENVIRONMENTAL-CURRENT-SENSOR-DATA","data":{"tact":"OFF","hact":"INIT","pm25":"FAIL","pm10":"NONE"}}"#.utf8)
        var state = DysonState()
        state.apply(try DysonMessageParser.parse(data))

        XCTAssertNil(state.roomTemperatureCelsius)
        XCTAssertNil(state.humidity)
        XCTAssertNil(state.pm25)
        XCTAssertNil(state.pm10)
    }

    func testCommandSerializationUsesDysonStateSetShape() throws {
        let data = try DysonCommandEncoder.fanSpeed(7, now: Date(timeIntervalSince1970: 0))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["msg"] as? String, "STATE-SET")
        XCTAssertEqual(object["time"] as? String, "1970-01-01T00:00:00Z")
        XCTAssertEqual(object["mode-reason"] as? String, "LAPP")
        let values = try XCTUnwrap(object["data"] as? [String: String])
        XCTAssertEqual(values["fpwr"], "ON")
        XCTAssertEqual(values["fnsp"], "0007")
    }

    func testEnvironmentalRequestUsesSensorDataMessage() throws {
        let data = try DysonCommandEncoder.requestEnvironmentalData(now: Date(timeIntervalSince1970: 0))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["msg"] as? String, "REQUEST-PRODUCT-ENVIRONMENT-CURRENT-SENSOR-DATA")
        XCTAssertEqual(object["time"] as? String, "1970-01-01T00:00:00Z")
    }

    func testComfortHeatingCommandTurnsOnHeatAtTheRequestedTemperature() throws {
        let data = try DysonCommandEncoder.comfortHeating(celsius: 24, now: Date(timeIntervalSince1970: 0))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let values = try XCTUnwrap(object["data"] as? [String: String])

        XCTAssertEqual(values["fpwr"], "ON")
        XCTAssertEqual(values["hmod"], "HEAT")
        XCTAssertEqual(values["hmax"], "2972")
    }

    func testCommandValidation() {
        XCTAssertThrowsError(try DysonCommandEncoder.fanSpeed(0))
        XCTAssertThrowsError(try DysonCommandEncoder.fanSpeed(11))
        XCTAssertThrowsError(try DysonCommandEncoder.oscillation(enabled: true, lowAngle: 10, highAngle: 20))
        XCTAssertNoThrow(try DysonCommandEncoder.oscillation(enabled: true, lowAngle: 90, highAngle: 270))
    }

    func testMovingOscillationSweepPreservesWidthAndSnapsDirection() {
        let range = OscillationRange(low: 90, high: 270).shifted(by: 23)
        XCTAssertEqual(range, OscillationRange(low: 115, high: 295))
        XCTAssertEqual(range.high - range.low, 180)
        XCTAssertNoThrow(try DysonCommandEncoder.oscillation(enabled: true, lowAngle: Int(range.low), highAngle: Int(range.high)))
    }

    func testMovingOscillationSweepStopsAtDeviceLimits() {
        let range = OscillationRange(low: 90, high: 270)
        XCTAssertEqual(range.shifted(by: -180), OscillationRange(low: 5, high: 185))
        XCTAssertEqual(range.shifted(by: 180), OscillationRange(low: 175, high: 355))
        XCTAssertEqual(OscillationRange(low: 5, high: 355).shifted(by: 45), OscillationRange(low: 5, high: 355))
    }

    func testMovingFixedOscillationDirectionKeepsEqualEndpoints() {
        XCTAssertEqual(OscillationRange(low: 180, high: 180).shifted(by: -35), OscillationRange(low: 145, high: 145))
    }

    func testCapabilitiesInferHP09Controls() {
        let capabilities = DysonCapabilities.inferred(model: "HP09", type: "527K", firmwareCapabilities: ["AdvanceOscillationDay1"])
        XCTAssertTrue(capabilities.heating)
        XCTAssertTrue(capabilities.targetTemperature)
        XCTAssertTrue(capabilities.oscillation)
        XCTAssertTrue(capabilities.oscillationAngle)
        XCTAssertTrue(capabilities.particulateMatter)
    }

    func testMalformedMessagesAreRejectedAndUnknownMessagesAreIgnored() {
        XCTAssertThrowsError(try DysonMessageParser.parse(Data("not-json".utf8)))
        XCTAssertEqual(try? DysonMessageParser.parse(Data(#"{"msg":"UNKNOWN"}"#.utf8)), .ignored("UNKNOWN"))
    }

    func testReconnectBackoffResetsAfterSuccessfulConnection() {
        var backoff = ReconnectBackoff(maximum: 60)
        XCTAssertEqual(backoff.nextDelay(), 1)
        XCTAssertEqual(backoff.nextDelay(), 2)
        XCTAssertEqual(backoff.nextDelay(), 4)
        backoff.reset()
        XCTAssertEqual(backoff.nextDelay(), 1)
    }

    func testComfortHeatingStartsBelowTargetAndStopsAtTarget() {
        var controller = ComfortHeatingController(
            targetTemperatureCelsius: 24,
            minimumHeatingDuration: 0,
            minimumIdleDuration: 0
        )
        let start = Date(timeIntervalSince1970: 0)

        XCTAssertEqual(controller.evaluate(roomTemperatureCelsius: 22, now: start), .startHeating)
        XCTAssertEqual(controller.phase, .heating)
        XCTAssertEqual(controller.evaluate(roomTemperatureCelsius: 24, now: start.addingTimeInterval(1)), .stopHeating)
        XCTAssertEqual(controller.phase, .idle)
    }

    func testComfortHeatingUsesHysteresisBeforeRestarting() {
        var controller = ComfortHeatingController(
            targetTemperatureCelsius: 24,
            hysteresisCelsius: 0.5,
            minimumHeatingDuration: 0,
            minimumIdleDuration: 0
        )
        let start = Date(timeIntervalSince1970: 0)

        XCTAssertEqual(controller.evaluate(roomTemperatureCelsius: 23, now: start), .startHeating)
        XCTAssertEqual(controller.evaluate(roomTemperatureCelsius: 24, now: start.addingTimeInterval(1)), .stopHeating)
        XCTAssertEqual(controller.evaluate(roomTemperatureCelsius: 23.6, now: start.addingTimeInterval(2)), .wait)
        XCTAssertEqual(controller.evaluate(roomTemperatureCelsius: 23.5, now: start.addingTimeInterval(3)), .startHeating)
    }

    func testComfortHeatingDefaultBandIsNarrow() {
        let controller = ComfortHeatingController(targetTemperatureCelsius: 24)

        XCTAssertEqual(controller.hysteresisCelsius, 0.2, accuracy: 0.001)
        XCTAssertEqual(controller.minimumHeatingDuration, 60, accuracy: 0.001)
        XCTAssertEqual(controller.minimumIdleDuration, 60, accuracy: 0.001)
    }

    func testComfortHeatingHonoursMinimumDwellTimes() {
        var controller = ComfortHeatingController(
            targetTemperatureCelsius: 24,
            minimumHeatingDuration: 120,
            minimumIdleDuration: 120
        )
        let start = Date(timeIntervalSince1970: 0)

        XCTAssertEqual(controller.evaluate(roomTemperatureCelsius: 22, now: start), .startHeating)
        XCTAssertEqual(controller.evaluate(roomTemperatureCelsius: 24, now: start.addingTimeInterval(60)), .wait)
        XCTAssertEqual(controller.evaluate(roomTemperatureCelsius: 24, now: start.addingTimeInterval(120)), .stopHeating)
        XCTAssertEqual(controller.evaluate(roomTemperatureCelsius: 23.5, now: start.addingTimeInterval(180)), .wait)
        XCTAssertEqual(controller.evaluate(roomTemperatureCelsius: 23.5, now: start.addingTimeInterval(240)), .startHeating)
    }
}
