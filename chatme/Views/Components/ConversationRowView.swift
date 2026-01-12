//
//  ConversationRowView.swift
//  chatme
//
//  Created by Claude on 2026/1/12.
//

import SwiftUI
import CoreData

struct ConversationRowView: View {
    let conversation: Conversation
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    // 会话标题
                    Text(conversation.title ?? "New Chat")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.black)
                        .lineLimit(1)

                    // 最后更新时间
                    Text(formattedDate)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var formattedDate: String {
        guard let updatedAt = conversation.updatedAt else { return "" }

        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(updatedAt) {
            formatter.timeStyle = .short
            return formatter.string(from: updatedAt)
        } else if Calendar.current.isDateInYesterday(updatedAt) {
            return "Yesterday"
        } else if Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.contains(updatedAt) == true {
            formatter.setLocalizedDateFormatFromTemplate("E") // 星期几
            return formatter.string(from: updatedAt)
        } else {
            formatter.dateStyle = .short
            return formatter.string(from: updatedAt)
        }
    }
}