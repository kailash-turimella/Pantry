import SwiftUI

struct ExpiryBadge: View {
    let status: ExpiryStatus
    var compact = false

    var body: some View {
        Text(status.label)
            .font(compact ? .caption2 : .caption)
            .fontWeight(.medium)
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, compact ? 2 : 4)
            .background(status.tint.opacity(0.15), in: Capsule())
            .foregroundStyle(status.tint)
    }
}

struct CategoryIcon: View {
    let category: FoodCategory

    var body: some View {
        Image(systemName: category.symbolName)
            .font(.system(size: 14))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(category.tint.gradient, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Standard empty state so the four tabs feel like one app.
struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// Inline error row used by the AI flows. Keeps failures visible and recoverable
/// instead of silently doing nothing.
struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.primary)
                if let retry {
                    Button("Try again", action: retry)
                        .font(.callout.weight(.medium))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Shown above anything Claude produced, before the user commits it.
struct ReviewNoticeBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.purple)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.purple.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }
}
