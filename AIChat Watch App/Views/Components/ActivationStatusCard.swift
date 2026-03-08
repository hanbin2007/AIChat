//
//  ActivationStatusCard.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/8.
//

import SwiftUI

struct ActivationStatusCard: View {
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
                    .foregroundStyle(.white)

                Spacer(minLength: 0)
            }

            Text(message)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.78))

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
                .fill(Color.black.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}
