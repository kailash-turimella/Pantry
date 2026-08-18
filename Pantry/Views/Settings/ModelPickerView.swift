import SwiftUI

/// Chooses which model handles one task. The recommendation is shown in bold
/// with the reasoning attached, so it reads as an argument you can disagree with
/// rather than a default you can't see the basis for.
struct ModelPickerView: View {
    let task: ClaudeTask
    /// Reports the new choice so the Settings list can update immediately —
    /// popping back doesn't re-evaluate the parent's body on its own.
    var onChange: (ClaudeModel) -> Void = { _ in }

    @State private var selection: ClaudeModel

    init(task: ClaudeTask, onChange: @escaping (ClaudeModel) -> Void = { _ in }) {
        self.task = task
        self.onChange = onChange
        _selection = State(initialValue: ModelPreferences.model(for: task))
    }

    var body: some View {
        List {
            Section {
                Text(task.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(ClaudeModel.allCases) { model in
                    Button {
                        selection = model
                        ModelPreferences.set(model, for: task)
                        onChange(model)
                    } label: {
                        row(for: model)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Model")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text("Why \(task.recommended.displayName) for this")
                            .fontWeight(.medium)
                    } icon: {
                        Image(systemName: "lightbulb")
                    }
                    .foregroundStyle(.primary)

                    Text(task.recommendationReason)
                }
                .font(.footnote)
                .padding(.top, 6)
            }
        }
        .navigationTitle(task.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(for model: ClaudeModel) -> some View {
        let isRecommended = model == task.recommended
        let isSelected = model == selection

        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    // The recommendation is the bold one.
                    Text(model.displayName)
                        .fontWeight(isRecommended ? .bold : .regular)
                    if isRecommended {
                        Text("Recommended")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                }

                Text(model.blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(model.priceLabel) · \(task.approximateCostLabel(for: model))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
