import Foundation
import CoreKit

/// Discrete door dynamics for a refrigerated truck. While the door is open, the cabin warms (the
/// `temperatureOffset`), which is what drives realistic temperature-threshold breaches.
public struct DoorBehavior: Sendable {
    public var openProbability: Double
    public var openDurationTicks: ClosedRange<Int>
    public var temperatureOffset: Double

    public init(openProbability: Double, openDurationTicks: ClosedRange<Int>, temperatureOffset: Double) {
        self.openProbability = openProbability
        self.openDurationTicks = openDurationTicks
        self.temperatureOffset = temperatureOffset
    }
}

/// Connectivity dynamics: occasionally the link drops for a few ticks. While offline the device emits
/// no readings — exactly the kind of gap a real fleet experiences and a good test for offline UX.
public struct ConnectivityBehavior: Sendable {
    public var dropProbability: Double
    public var outageDurationTicks: ClosedRange<Int>

    public init(dropProbability: Double, outageDurationTicks: ClosedRange<Int>) {
        self.dropProbability = dropProbability
        self.outageDurationTicks = outageDurationTicks
    }

    public static let stable = ConnectivityBehavior(dropProbability: 0, outageDurationTicks: 1...1)
}

/// Simple planar GPS drift for moving assets (trucks): the position walks with a slowly turning
/// heading, bouncing off the coordinate bounds so it never leaves the Earth.
public struct MotionBehavior: Sendable {
    public var latitude: Double
    public var longitude: Double
    public var heading: Double
    public var speed: Double          // degrees per tick
    public var headingJitter: Double

    public init(latitude: Double, longitude: Double, heading: Double, speed: Double, headingJitter: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.heading = heading
        self.speed = speed
        self.headingJitter = headingJitter
    }
}

/// The evolving position of a moving device.
struct MotionState: Sendable {
    var latitude: Double
    var longitude: Double
    var heading: Double
    let speed: Double
    let headingJitter: Double

    init(_ behavior: MotionBehavior) {
        latitude = behavior.latitude
        longitude = behavior.longitude
        heading = behavior.heading
        speed = behavior.speed
        headingJitter = behavior.headingJitter
    }

    mutating func advance(using rng: inout SeededRandomNumberGenerator) {
        heading += rng.nextGaussian(standardDeviation: headingJitter)
        latitude += speed * Foundation.cos(heading)
        longitude += speed * Foundation.sin(heading)
        if !(-90.0...90.0).contains(latitude) {
            latitude = latitude.clamped(to: -90...90)
            heading = -heading            // bounce
        }
        if !(-180.0...180.0).contains(longitude) {
            longitude = longitude.clamped(to: -180...180)
            heading = .pi - heading
        }
    }
}
