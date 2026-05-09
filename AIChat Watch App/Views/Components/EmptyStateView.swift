//
//  EmptyStateView.swift
//  AIChat Watch App
//
//  Shared empty-state primitive: SF Symbol + title + optional subtitle
//  + optional CTA button. Used in conversation list, favorites, prompt
//  library, archive browser, and global pinned memory screens.
//

import SwiftUI

struct EmptyStateView: View {
    let symbol: String
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: DS.Spacing.s) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.secondary)
            Text(title)
                .font(DS.Typography.listTitle)
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(DS.Typography.listPreview)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(.top, DS.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.l)
    }
}
