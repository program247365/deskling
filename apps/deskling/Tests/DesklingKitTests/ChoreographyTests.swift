import DesklingKit
import XCTest

final class ChoreographyTests: XCTestCase {
    func testQueuePlaysEveryActOnceBeforeRepeating() {
        var queue = ActQueue(names: ["a", "b", "c", "d", "e"])
        var rng = Seeded(1)
        let first = (0..<5).compactMap { _ in queue.next(using: &rng) }
        let second = (0..<5).compactMap { _ in queue.next(using: &rng) }
        XCTAssertEqual(Set(first).count, 5)
        XCTAssertEqual(Set(second).count, 5)
    }

    func testEmptyQueueReturnsNil() {
        var queue = ActQueue(names: [])
        var rng = Seeded(1)
        XCTAssertNil(queue.next(using: &rng))
    }

    func testShortActsPlayTwice() {
        XCTAssertEqual(Choreography.plays(forFrameCount: 39), 2)
        XCTAssertEqual(Choreography.plays(forFrameCount: 40), 1)
    }

    func testWalkStopsStayInBoundsAndCoverAThird() {
        var rng = Seeded(7)
        var x: CGFloat = 40
        var facing = Facing.right
        let maxX: CGFloat = 1200
        for _ in 0..<500 {
            let stop = Choreography.nextWalkStop(from: x, facing: facing, maxX: maxX, using: &rng)
            XCTAssertTrue((0...maxX).contains(stop))
            if stop != 0 && stop != maxX {
                XCTAssertGreaterThanOrEqual(abs(stop - x), maxX / 3 - 0.001)
            }
            facing = stop >= x ? .right : .left
            x = stop
        }
    }

    func testWalkStopWithNoRoomReturnsZero() {
        var rng = Seeded(3)
        XCTAssertEqual(Choreography.nextWalkStop(from: 0, facing: .right, maxX: 0, using: &rng), 0)
    }

    func testStepMovesAtWalkSpeed() {
        let result = Choreography.step(x: 0, toward: 500, width: 180, elapsed: 0.016)
        XCTAssertEqual(result.x, 180 * 140.0 / 360.0 * 0.016, accuracy: 0.0001)
        XCTAssertFalse(result.arrived)
    }

    func testStepMovesLeftTowardALowerTarget() {
        let result = Choreography.step(x: 500, toward: 0, width: 180, elapsed: 0.016)
        XCTAssertEqual(result.x, 500 - 180 * 140.0 / 360.0 * 0.016, accuracy: 0.0001)
    }

    func testStepClampsLongGaps() {
        let result = Choreography.step(x: 0, toward: 5000, width: 180, elapsed: 3600)
        XCTAssertEqual(result.x, 180 * 140.0 / 360.0 * 0.05, accuracy: 0.0001)
    }

    func testStepStopsExactlyAtTarget() {
        let right = Choreography.step(x: 9.9, toward: 10, width: 180, elapsed: 0.05)
        XCTAssertEqual(right.x, 10)
        XCTAssertTrue(right.arrived)
        let left = Choreography.step(x: 10.1, toward: 10, width: 180, elapsed: 0.05)
        XCTAssertEqual(left.x, 10)
        XCTAssertTrue(left.arrived)
    }

    func testDropStartsAtTheTop() {
        let drop = Choreography.drop(from: 900, to: 0, elapsed: 0)
        XCTAssertEqual(drop.y, 900)
        XCTAssertFalse(drop.landed)
    }

    func testDropAcceleratesLikeAFall() {
        let early = Choreography.drop(from: 900, to: 0, elapsed: 0.2)
        let later = Choreography.drop(from: 900, to: 0, elapsed: 0.4)
        XCTAssertEqual(early.y, 900 - 0.5 * Choreography.gravity * 0.04, accuracy: 0.001)
        // Falls three times as far in the second 0.2s as in the first.
        XCTAssertEqual(early.y - later.y, 3 * (900 - early.y), accuracy: 0.001)
        XCTAssertFalse(later.landed)
    }

    func testDropLandsExactlyOnTheFloorAndStaysThere() {
        let landing = Choreography.drop(from: 900, to: 12, elapsed: 5)
        XCTAssertEqual(landing.y, 12)
        XCTAssertTrue(landing.landed)
        XCTAssertEqual(Choreography.drop(from: 900, to: 12, elapsed: 3600).y, 12)
    }

    func testRiseIsTheDropPlayedBackwards() {
        let start = Choreography.rise(from: 12, to: 900, elapsed: 0)
        XCTAssertEqual(start.y, 12)
        XCTAssertFalse(start.gone)
        // As far up from the floor as the drop is down from the top, at every moment.
        let rise = Choreography.rise(from: 12, to: 900, elapsed: 0.3)
        let drop = Choreography.drop(from: 900, to: 12, elapsed: 0.3)
        XCTAssertEqual(rise.y - 12, 900 - drop.y, accuracy: 0.001)
        XCTAssertFalse(rise.gone)
    }

    func testRiseStopsAtTheTopAndStaysThere() {
        let gone = Choreography.rise(from: 12, to: 900, elapsed: 5)
        XCTAssertEqual(gone.y, 900)
        XCTAssertTrue(gone.gone)
    }

    func testDropFromBelowTheFloorLandsAtOnce() {
        let drop = Choreography.drop(from: 5, to: 40, elapsed: 0)
        XCTAssertEqual(drop.y, 40)
        XCTAssertTrue(drop.landed)
    }

    func testARoamingClawdTeleportsAboutOneTimeInFour() {
        var rng = Seeded(11)
        let hits = (0..<4000).filter { _ in Choreography.shouldTeleport(roams: true, using: &rng) }.count
        XCTAssertEqual(Double(hits) / 4000, 0.25, accuracy: 0.03)
    }

    func testAClawdKeptAtTheBottomNeverTeleports() {
        var rng = Seeded(11)
        let hits = (0..<4000).filter { _ in Choreography.shouldTeleport(roams: false, using: &rng) }.count
        XCTAssertEqual(hits, 0)
    }
}
