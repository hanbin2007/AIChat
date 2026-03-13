//
//  MarkdownRendererConfiguration.Math.swift
//  MarkdownView
//
//  Created by LiYanan2004 on 2025/4/16.
//

import Foundation

extension MarkdownRendererConfiguration {
    struct Math: Sendable, Hashable {
        struct RenderIssue: Sendable, Hashable {
            var rawValue: String
            var message: String
        }

        var shouldRender: Bool {
            get { displayMathStorage != nil }
            set(enabled) {
                if enabled {
                    displayMathStorage = [:]
                    displayMathIssueStorage = [:]
                } else {
                    displayMathStorage = nil
                    displayMathIssueStorage = nil
                }
            }
        }
        var displayMathStorage: [UUID : String]? = nil
        var displayMathIssueStorage: [UUID : RenderIssue]? = nil
        
        mutating func appendDisplayMath(_ displayMath: some StringProtocol) -> UUID {
            if displayMathStorage == nil {
                displayMathStorage = [:]
            }
            
            let id = UUID()
            displayMathStorage![id] = String(displayMath)
            return id
        }

        mutating func appendDisplayMathIssue(
            rawValue: some StringProtocol,
            message: some StringProtocol
        ) -> UUID {
            if displayMathIssueStorage == nil {
                displayMathIssueStorage = [:]
            }

            let id = UUID()
            displayMathIssueStorage![id] = RenderIssue(
                rawValue: String(rawValue),
                message: String(message)
            )
            return id
        }
    }
}
