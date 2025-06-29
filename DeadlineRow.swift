//
//  DeadlineRow.swift
//  Deadline Calendar
//
//  Created by Aidan O'Brien on 20/4/2024.
//

import SwiftUI

struct DeadlineRow: View {
    let item: UnifiedDeadlineItem

    var body: some View {
        HStack {
            // Checkbox - functionality to be added
            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(item.isCompleted ? .green : .gray)

            VStack(alignment: .leading) {
                Text(item.title)
                    .font(.headline)
                
                if let projectTitle = item.originatingProjectTitle {
                    Text(projectTitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Text(item.date, style: .date)
                    .font(.caption)
                    .foregroundColor(dateColor(for: item.date))
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private func dateColor(for date: Date) -> Color {
        if Calendar.current.isDateInToday(date) {
            return .orange
        } else if date < Date() {
            return .red
        }
        return .secondary
    }
} 