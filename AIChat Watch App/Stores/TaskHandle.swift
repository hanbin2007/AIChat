//
//  TaskHandle.swift
//  AIChat Watch App
//
//  Sendable mutable box around a `Task` reference. Lets `@MainActor`
//  ViewModels store an in-flight Task as `let handle = TaskHandle()`
//  (immutable property, no isolation pinning) while still letting the
//  nonisolated `deinit` cancel whatever's inside. Plain
//  `nonisolated var task: Task?` would compile-error in Swift 6 —
//  `nonisolated` is not allowed on mutable stored properties — and
//  `nonisolated(unsafe)` was the old workaround.
//

import Foundation

final class TaskHandle: @unchecked Sendable {
    var task: Task<Void, Never>?

    func cancel() {
        task?.cancel()
        task = nil
    }
}
