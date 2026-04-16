//
//  AppBackdropView.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/7.
//

import SwiftUI

struct AppBackdropView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: backdropColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            #if os(watchOS)
            // watchOS: use larger radii with no blur to avoid GPU-expensive
            // gaussian passes on the S-series SiP.
            Circle()
                .fill(primaryOrbColor)
                .frame(width: 180, height: 180)
                .offset(x: 44, y: -56)

            Circle()
                .fill(secondaryOrbColor)
                .frame(width: 140, height: 140)
                .offset(x: -48, y: 84)
            #else
            Circle()
                .fill(primaryOrbColor)
                .frame(width: 120, height: 120)
                .blur(radius: 22)
                .offset(x: 44, y: -56)

            Circle()
                .fill(secondaryOrbColor)
                .frame(width: 90, height: 90)
                .blur(radius: 18)
                .offset(x: -48, y: 84)
            #endif
        }
        .ignoresSafeArea()
    }

    private var backdropColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.02, green: 0.03, blue: 0.08),
                Color(red: 0.04, green: 0.15, blue: 0.22),
                Color(red: 0.02, green: 0.05, blue: 0.09)
            ]
        }

        return [
            Color(red: 0.96, green: 0.98, blue: 1.0),
            Color(red: 0.88, green: 0.95, blue: 0.98),
            Color(red: 0.93, green: 0.96, blue: 0.99)
        ]
    }

    private var primaryOrbColor: Color {
        colorScheme == .dark ? Color.cyan.opacity(0.16) : Color.cyan.opacity(0.14)
    }

    private var secondaryOrbColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }
}
