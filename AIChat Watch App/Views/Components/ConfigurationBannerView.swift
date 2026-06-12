//
//  ConfigurationBannerView.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/7.
//

import SwiftUI

struct ConfigurationBannerView: View {
    @Environment(\.colorScheme) private var colorScheme

    var iconName: String = "key.fill"
    var title: String = "Gemini Setup"
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.headline)
                .foregroundStyle(.cyan)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(DS.Text.primary(for: colorScheme))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(DS.Text.secondary(for: colorScheme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(DS.Surface.elevatedFill(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(DS.Surface.elevatedStroke(for: colorScheme), lineWidth: 1)
                )
        )
    }
}
