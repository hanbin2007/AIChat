//
//  AppBackdropView.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/7.
//

import SwiftUI

struct AppBackdropView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.03, blue: 0.08),
                    Color(red: 0.04, green: 0.15, blue: 0.22),
                    Color(red: 0.02, green: 0.05, blue: 0.09)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.cyan.opacity(0.16))
                .frame(width: 120, height: 120)
                .blur(radius: 22)
                .offset(x: 44, y: -56)

            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 90, height: 90)
                .blur(radius: 18)
                .offset(x: -48, y: 84)
        }
        .ignoresSafeArea()
    }
}
