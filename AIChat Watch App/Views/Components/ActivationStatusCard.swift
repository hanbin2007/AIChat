//
//  ActivationStatusCard.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/8.
//

import SwiftUI

struct ActivationStatusCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let message: String
    let iconName: String
    let accentColor: Color
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        title: String,
        message: String,
        iconName: String = "key.fill",
        accentColor: Color = .orange,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.iconName = iconName
        self.accentColor = accentColor
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.headline)
                    .foregroundStyle(accentColor)

                Text(title)
                    .font(.headline)
                    .foregroundStyle(DS.Text.primary(for: colorScheme))

                Spacer(minLength: 0)
            }

            Text(message)
                .font(.footnote)
                .foregroundStyle(DS.Text.secondary(for: colorScheme))

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(accentColor)
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
