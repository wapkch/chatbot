//
//  ChatNavigationBar.swift
//  chatme
//
//  Created by Claude on 2026/1/12.
//

import SwiftUI

struct ChatNavigationBar: View {
    let title: String
    let onToggleSidebar: () -> Void
    let onNewChat: () -> Void

    var body: some View {
        HStack {
            // 汉堡菜单按钮（左上角）
            Button(action: onToggleSidebar) {
                Image(systemName: "line.horizontal.3")
                    .font(.title2)
                    .foregroundColor(.primary)
            }
            .accessibilityLabel("Open chat history")

            Spacer()

            // 应用标题
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            Spacer()

            // 新会话按钮（右上角）
            Button(action: onNewChat) {
                Image(systemName: "square.and.pencil")
                    .font(.title2)
                    .foregroundColor(.primary)
            }
            .accessibilityLabel("Start new conversation")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
}