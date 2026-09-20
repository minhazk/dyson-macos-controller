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

    func testCommandValidation() {
        XCTAssertThrowsError(try DysonCommandEncoder.fanSpeed(0))
        XCTAssertThrowsError(try DysonCommandEncoder.fanSpeed(11))
        XCTAssertThrowsError(try DysonCommandEncoder.oscillation(enabled: true, lowAngle: 10, highAngle: 20))
        XCTAssertNoThrow(try DysonCommandEncoder.oscillation(enabled: true, lowAngle: 90, highAngle: 270))
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
}
