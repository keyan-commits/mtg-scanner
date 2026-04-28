import Testing
@testable import MTGCardScanner

@Suite("EmptyFrameCounter")
struct EmptyFrameCounterTests {

    @Test("Initial state has zero count and does not fire")
    func initialState() {
        var counter = EmptyFrameCounter(threshold: 6)
        #expect(counter.count == 0)
    }

    @Test("Present frame keeps count at zero")
    func presentFrameKeepsZero() {
        var counter = EmptyFrameCounter(threshold: 6)
        let fired = counter.observe(rectanglePresent: true)
        #expect(fired == false)
        #expect(counter.count == 0)
    }

    @Test("Below-threshold absent frames do not fire")
    func belowThresholdQuiet() {
        var counter = EmptyFrameCounter(threshold: 6)
        for _ in 0..<5 {
            #expect(counter.observe(rectanglePresent: false) == false)
        }
        #expect(counter.count == 5)
    }

    @Test("Crossing the threshold fires exactly once")
    func crossingFiresOnce() {
        var counter = EmptyFrameCounter(threshold: 6)
        // Frames 1..5 — no fire.
        for _ in 0..<5 {
            #expect(counter.observe(rectanglePresent: false) == false)
        }
        // Frame 6 — fires.
        #expect(counter.observe(rectanglePresent: false) == true)
        // Counter resets after firing so the caller doesn't get repeated triggers
        // while the card stays out of frame.
        #expect(counter.count == 0)
        // Frame 7 — quiet again until the next 6-frame run.
        #expect(counter.observe(rectanglePresent: false) == false)
    }

    @Test("Present frame interrupts the absence run")
    func presentInterruptsRun() {
        var counter = EmptyFrameCounter(threshold: 6)
        for _ in 0..<5 {
            counter.observe(rectanglePresent: false)
        }
        #expect(counter.count == 5)
        counter.observe(rectanglePresent: true)
        #expect(counter.count == 0)
        // Now the next absent run starts from scratch — a single absent frame
        // shouldn't fire.
        #expect(counter.observe(rectanglePresent: false) == false)
    }

    @Test("Multiple full cycles fire each time")
    func multipleCyclesFire() {
        var counter = EmptyFrameCounter(threshold: 3)
        for cycle in 0..<5 {
            counter.observe(rectanglePresent: true)
            #expect(counter.observe(rectanglePresent: false) == false, "cycle \(cycle) frame 1")
            #expect(counter.observe(rectanglePresent: false) == false, "cycle \(cycle) frame 2")
            #expect(counter.observe(rectanglePresent: false) == true,  "cycle \(cycle) frame 3")
        }
    }

    @Test("Manual reset clears the count")
    func manualResetClears() {
        var counter = EmptyFrameCounter(threshold: 6)
        counter.observe(rectanglePresent: false)
        counter.observe(rectanglePresent: false)
        #expect(counter.count == 2)
        counter.reset()
        #expect(counter.count == 0)
    }

    @Test("Lower threshold fires earlier")
    func lowerThresholdFiresEarlier() {
        var counter = EmptyFrameCounter(threshold: 2)
        #expect(counter.observe(rectanglePresent: false) == false)
        #expect(counter.observe(rectanglePresent: false) == true)
    }
}
