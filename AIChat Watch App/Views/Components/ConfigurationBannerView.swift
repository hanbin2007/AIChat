//
//  ConfigurationBannerView.swift
//  AIChat Watch App
//
//  Inline banner the Home screen shows when relay is misconfigured
//  (no base URL, missing bearer, persistent connection failure). Tapping
//  the banner pushes the AccountCenterView so the user can re-bootstrap.
//

import SwiftUI

struct ConfigurationBannerView: View {
    let message: String
    var severity: Severity = .warning
    var action: (() -> Void)?

    enum Severity {
        case warning
        case error
    }

    var body: some View {
        HStack(spacing: DS.Spacing.s) {
            Image(systemName: severity == .error ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(severity == .error ? DS.Status.danger : DS.Status.warn)
            Text(message)
                .font(DS.Typography.listPreview)
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer(minLength: 0)
            if action != nil {
                Image(systemName: "chevron.forward")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, DS.Spacing.m)
        .padding(.vertical, DS.Spacing.s)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .onTapGesture {
            action?()
        }
    }
}
