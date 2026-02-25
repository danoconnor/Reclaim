//
//  BatchProcessorTests.swift
//  ReclaimTests
//
//  Created by Dan O'Connor on 2/16/26.
//

import XCTest
@testable import Reclaim

class BatchProcessorTests: XCTestCase {

    // MARK: - Edge Cases

    func testProcess_EmptyInput_ReturnsEmptyArray() async {
        let results = await BatchProcessor.process(
            items: [Int](),
            batchSize: 4,
            transform: { $0 * 2 }
        )
        XCTAssertTrue(results.isEmpty)
    }

    func testProcess_BatchSizeZero_ReturnsEmptyArray() async {
        let results = await BatchProcessor.process(
            items: [1, 2, 3],
            batchSize: 0,
            transform: { $0 * 2 }
        )
        XCTAssertTrue(results.isEmpty)
    }

    func testProcess_SingleItem_ReturnsTransformedItem() async {
        let results = await BatchProcessor.process(
            items: [5],
            batchSize: 4,
            transform: { $0 * 3 }
        )
        XCTAssertEqual(results, [15])
    }

    // MARK: - Batch Sizing

    func testProcess_ItemsFewerThanBatchSize_ProcessedInOneBatch() async {
        var batchCompleteCount = 0

        let results = await BatchProcessor.process(
            items: [1, 2, 3],
            batchSize: 10,
            transform: { $0 * 2 },
            onBatchComplete: { _ in batchCompleteCount += 1 }
        )

        XCTAssertEqual(results, [2, 4, 6])
        XCTAssertEqual(batchCompleteCount, 1, "Should complete in exactly one batch")
    }

    func testProcess_ItemsEqualToBatchSize_ProcessedInOneBatch() async {
        var batchCompleteCount = 0

        let results = await BatchProcessor.process(
            items: [1, 2, 3, 4],
            batchSize: 4,
            transform: { $0 + 10 },
            onBatchComplete: { _ in batchCompleteCount += 1 }
        )

        XCTAssertEqual(results, [11, 12, 13, 14])
        XCTAssertEqual(batchCompleteCount, 1, "Should complete in exactly one batch")
    }

    func testProcess_ItemsMoreThanBatchSize_MultipleBatches() async {
        var batchCompleteCount = 0

        let results = await BatchProcessor.process(
            items: Array(1...10),
            batchSize: 4,
            transform: { $0 },
            onBatchComplete: { _ in batchCompleteCount += 1 }
        )

        XCTAssertEqual(results, Array(1...10))
        XCTAssertEqual(batchCompleteCount, 3, "10 items with batch size 4 = 3 batches (4+4+2)")
    }

    func testProcess_ExactMultipleOfBatchSize() async {
        var batchCompleteCount = 0

        let results = await BatchProcessor.process(
            items: Array(1...12),
            batchSize: 4,
            transform: { $0 },
            onBatchComplete: { _ in batchCompleteCount += 1 }
        )

        XCTAssertEqual(results, Array(1...12))
        XCTAssertEqual(batchCompleteCount, 3, "12 items with batch size 4 = exactly 3 batches")
    }

    func testProcess_BatchSizeOfOne_SequentialProcessing() async {
        var batchCompleteCount = 0
        var progressCounts: [Int] = []

        let results = await BatchProcessor.process(
            items: [10, 20, 30],
            batchSize: 1,
            transform: { $0 / 10 },
            onBatchComplete: { count in
                batchCompleteCount += 1
                progressCounts.append(count)
            }
        )

        XCTAssertEqual(results, [1, 2, 3])
        XCTAssertEqual(batchCompleteCount, 3, "Batch size 1 means each item is its own batch")
        XCTAssertEqual(progressCounts, [1, 2, 3])
    }

    // MARK: - Order Preservation

    func testProcess_PreservesOrderWithVariableProcessingTime() async {
        // Items that take different amounts of time to process
        // should still return in original order
        let items = Array(0..<20)

        let results = await BatchProcessor.process(
            items: items,
            batchSize: 4,
            transform: { item -> Int in
                // Reverse delay: earlier items take longer
                let delay = UInt64((20 - item) * 1_000_000) // 1-20ms
                try? await Task.sleep(nanoseconds: delay)
                return item
            }
        )

        XCTAssertEqual(results, items, "Results must preserve original input order")
    }

    func testProcess_PreservesOrderAcrossBatchBoundaries() async {
        // Verify items at batch boundaries maintain correct order
        let items = Array(0..<9) // 3 batches of 3

        let results = await BatchProcessor.process(
            items: items,
            batchSize: 3,
            transform: { $0 * 10 }
        )

        XCTAssertEqual(results, [0, 10, 20, 30, 40, 50, 60, 70, 80])
    }

    // MARK: - Progress Tracking

    func testProcess_ProgressCallbackCumulativeCounts() async {
        var progressCounts: [Int] = []

        _ = await BatchProcessor.process(
            items: Array(1...7),
            batchSize: 3,
            transform: { $0 },
            onBatchComplete: { count in progressCounts.append(count) }
        )

        // 3 batches: [1,2,3], [4,5,6], [7]
        XCTAssertEqual(progressCounts, [3, 6, 7], "Progress should report cumulative counts after each batch")
    }

    func testProcess_ProgressCallbackNotCalledForEmptyInput() async {
        var callbackCalled = false

        _ = await BatchProcessor.process(
            items: [Int](),
            batchSize: 4,
            transform: { $0 },
            onBatchComplete: { _ in callbackCalled = true }
        )

        XCTAssertFalse(callbackCalled, "Progress callback should not be called for empty input")
    }

    func testProcess_ProgressCallbackFinalCountMatchesItemCount() async {
        var finalCount = 0

        _ = await BatchProcessor.process(
            items: Array(1...13),
            batchSize: 4,
            transform: { $0 },
            onBatchComplete: { count in finalCount = count }
        )

        XCTAssertEqual(finalCount, 13, "Final progress count should equal total item count")
    }

    // MARK: - Transform Function

    func testProcess_TransformAppliedToEachItem() async {
        let items = ["hello", "world", "swift"]

        let results = await BatchProcessor.process(
            items: items,
            batchSize: 2,
            transform: { $0.uppercased() }
        )

        XCTAssertEqual(results, ["HELLO", "WORLD", "SWIFT"])
    }

    func testProcess_TypeConversion() async {
        let items = [1, 2, 3, 4, 5]

        let results: [String] = await BatchProcessor.process(
            items: items,
            batchSize: 3,
            transform: { "Number: \($0)" }
        )

        XCTAssertEqual(results, ["Number: 1", "Number: 2", "Number: 3", "Number: 4", "Number: 5"])
    }

    func testProcess_AsyncTransformProducesCorrectResults() async {
        let results = await BatchProcessor.process(
            items: [1, 2, 3, 4, 5],
            batchSize: 2,
            transform: { item -> String in
                // Simulate async work
                try? await Task.sleep(nanoseconds: 10_000_000)
                return "item_\(item)"
            }
        )

        XCTAssertEqual(results, ["item_1", "item_2", "item_3", "item_4", "item_5"])
    }

    // MARK: - Scale

    func testProcess_LargeInput_AllItemsProcessed() async {
        let count = 100
        let items = Array(0..<count)

        let results = await BatchProcessor.process(
            items: items,
            batchSize: 4,
            transform: { $0 * 2 }
        )

        XCTAssertEqual(results.count, count)
        for (index, value) in results.enumerated() {
            XCTAssertEqual(value, index * 2, "Item at index \(index) should be \(index * 2)")
        }
    }

    func testProcess_LargeInput_CorrectBatchCount() async {
        let count = 100
        var batchCompleteCount = 0

        _ = await BatchProcessor.process(
            items: Array(0..<count),
            batchSize: 4,
            transform: { $0 },
            onBatchComplete: { _ in batchCompleteCount += 1 }
        )

        XCTAssertEqual(batchCompleteCount, 25, "100 items / batch size 4 = 25 batches")
    }

    // MARK: - Concurrency Behavior

    func testProcess_ItemsWithinBatchRunConcurrently() async {
        // Verify items within a batch are processed concurrently, not sequentially.
        // If 4 items each take ~50ms and run concurrently, total should be ~50ms, not ~200ms.
        let batchSize = 4
        let delayPerItem: UInt64 = 50_000_000 // 50ms

        let start = CFAbsoluteTimeGetCurrent()

        _ = await BatchProcessor.process(
            items: Array(0..<batchSize),
            batchSize: batchSize,
            transform: { _ -> Int in
                try? await Task.sleep(nanoseconds: delayPerItem)
                return 0
            }
        )

        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let elapsedMs = elapsed * 1000

        // Sequential would be ~200ms. Concurrent should be ~50ms.
        // Use generous threshold to avoid flaky test.
        XCTAssertLessThan(elapsedMs, 150, "Batch should process items concurrently (took \(Int(elapsedMs))ms, expected <150ms)")
    }

    func testProcess_BatchesRunSequentially() async {
        // Verify batches themselves run sequentially (second batch shouldn't start
        // until first batch completes). Track batch start/end ordering.
        var batchOrder: [Int] = []
        let lock = NSLock()

        _ = await BatchProcessor.process(
            items: Array(0..<8),
            batchSize: 4,
            transform: { $0 },
            onBatchComplete: { count in
                lock.lock()
                batchOrder.append(count)
                lock.unlock()
            }
        )

        // Batches must complete in order: 4, then 8
        XCTAssertEqual(batchOrder, [4, 8], "Batches should complete sequentially in order")
    }
}
