//
//  BatchProcessor.swift
//  Reclaim
//
//  Created by Dan O'Connor on 2/16/26.
//

import Foundation

/// A utility for processing items in batches with limited concurrency while preserving order.
struct BatchProcessor {
    /// Processes items in batches with limited concurrency, preserving the original order.
    ///
    /// Items are divided into batches of `batchSize`. Within each batch, items are processed
    /// concurrently using a task group. Results maintain the same order as the input items.
    ///
    /// - Parameters:
    ///   - items: The items to process.
    ///   - batchSize: Maximum number of items to process concurrently in each batch.
    ///   - transform: An async closure that transforms each input item into an output.
    ///   - onBatchComplete: Optional callback invoked after each batch completes, with the
    ///     cumulative count of processed items so far.
    /// - Returns: An array of transformed items in the same order as the input.
    static func process<Input, Output>(
        items: [Input],
        batchSize: Int,
        transform: @escaping (Input) async -> Output,
        onBatchComplete: ((Int) -> Void)? = nil
    ) async -> [Output] {
        guard batchSize > 0, !items.isEmpty else { return [] }

        var results: [Output] = []
        results.reserveCapacity(items.count)
        var processedCount = 0

        for batchStart in stride(from: 0, to: items.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, items.count)
            let batch = Array(items[batchStart..<batchEnd])

            let batchResults = await withTaskGroup(of: (Int, Output).self) { group in
                for (offset, item) in batch.enumerated() {
                    group.addTask {
                        let result = await transform(item)
                        return (offset, result)
                    }
                }

                var batchItems: [(Int, Output)] = []
                for await item in group {
                    batchItems.append(item)
                }
                return batchItems.sorted(by: { $0.0 < $1.0 }).map { $0.1 }
            }

            results.append(contentsOf: batchResults)
            processedCount += batchResults.count
            onBatchComplete?(processedCount)
        }

        return results
    }
}
