import PhotosUI
import SwiftData
import SwiftUI

/// Editable version of an item Claude spotted. Nothing is written to the store
/// until the user taps Save on the review screen.
struct ItemDraft: Identifiable {
    let id = UUID()
    var include = true
    var name: String
    var quantity: Double
    var unit: MeasureUnit
    var category: FoodCategory
    var hasExpiry: Bool
    var expiryDate: Date
    /// True when the date came off the packaging rather than being estimated later.
    var expiryWasPrinted: Bool
    var confidence: String

    init(from extracted: ExtractedItem) {
        name = extracted.name
        quantity = extracted.quantity
        unit = extracted.resolvedUnit
        category = extracted.resolvedCategory
        confidence = extracted.confidence
        if let printed = extracted.resolvedExpiry {
            hasExpiry = true
            expiryDate = printed
            expiryWasPrinted = true
        } else {
            hasExpiry = false
            expiryDate = Date()
            expiryWasPrinted = false
        }
    }
}

struct PhotoAddFlowView: View {
    private enum Stage: Equatable {
        case choosing
        case analyzing
        case review
        case failed(String)
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var stage: Stage = .choosing
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var images: [UIImage] = []
    @State private var drafts: [ItemDraft] = []
    @State private var claudeNotes: String?
    @State private var showingCamera = false
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    if stage == .review {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") { save() }
                                .disabled(selectedCount == 0 || isSaving)
                        }
                    }
                }
                .fullScreenCover(isPresented: $showingCamera) {
                    CameraPicker { image in
                        images = [image]
                        Task { await analyze() }
                    }
                    .ignoresSafeArea()
                }
                .onChange(of: pickerItems) { _, newValue in
                    guard !newValue.isEmpty else { return }
                    Task { await loadPickedImages(newValue) }
                }
        }
    }

    private var navigationTitle: String {
        switch stage {
        case .choosing: return "Add from photo"
        case .analyzing: return "Reading photo"
        case .review: return "Check before saving"
        case .failed: return "Add from photo"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .choosing:
            chooser
        case .analyzing:
            VStack(spacing: 16) {
                ProgressView()
                Text("Working out what's in the photo…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .review:
            reviewList
        case .failed(let message):
            VStack(spacing: 20) {
                ErrorBanner(message: message) {
                    Task { await analyze() }
                }
                Button("Pick a different photo") { stage = .choosing }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: - Choosing

    private var chooser: some View {
        VStack(spacing: 24) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("Photograph your shopping and Pantry will fill in the details for you to check.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            VStack(spacing: 12) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showingCamera = true
                    } label: {
                        Label("Take a photo", systemImage: "camera")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: 3,
                    matching: .images
                ) {
                    Label("Choose from library", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 32)

            if !APIKeyStore.hasKey {
                Text("Add an Anthropic API key in Settings to use this.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Review

    private var reviewList: some View {
        List {
            Section {
                ReviewNoticeBanner(
                    message: "Claude read these off your photo. Edit anything that's wrong, untick what you don't want, then save."
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if let claudeNotes, !claudeNotes.isEmpty {
                Section {
                    Text(claudeNotes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if drafts.isEmpty {
                Section {
                    Text("Nothing recognisable turned up in that photo.")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach($drafts) { $draft in
                Section {
                    ItemDraftEditor(draft: $draft)
                }
            }
        }
    }

    private var selectedCount: Int { drafts.filter(\.include).count }

    // MARK: - Work

    private func loadPickedImages(_ items: [PhotosPickerItem]) async {
        var loaded: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                loaded.append(image)
            }
        }
        guard !loaded.isEmpty else {
            stage = .failed("Couldn't open those photos.")
            return
        }
        images = loaded
        await analyze()
    }

    private func analyze() async {
        guard !images.isEmpty else { return }
        stage = .analyzing
        do {
            let result = try await PhotoItemExtractor.extract(from: images)
            drafts = result.items.map(ItemDraft.init(from:))
            claudeNotes = result.notes
            stage = .review
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    private func save() {
        isSaving = true
        Task {
            for draft in drafts where draft.include {
                let name = draft.name.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { continue }

                // A date here came off the packaging or was typed in — either way
                // it's a real date, not an estimate.
                var expiry: Date? = draft.hasExpiry ? draft.expiryDate : nil
                var source: ExpirySource = draft.hasExpiry ? .manual : .none
                var note: String?

                // Nothing printed on the packaging and nothing typed in: fall back
                // to the shelf-life estimator so it still ages correctly.
                if expiry == nil {
                    if let result = await ShelfLifeEstimator.estimate(for: name, category: draft.category) {
                        expiry = result.estimate.suggestedDate
                        source = .estimated
                        note = result.estimate.note
                    }
                }

                context.insert(
                    InventoryItem(
                        name: name,
                        quantity: draft.quantity,
                        unit: draft.unit,
                        category: draft.category,
                        expiryDate: expiry,
                        expirySource: expiry == nil ? .none : source,
                        estimateNote: note
                    )
                )
            }
            try? context.save()
            isSaving = false
            dismiss()
        }
    }
}

// MARK: - Row editor

private struct ItemDraftEditor: View {
    @Binding var draft: ItemDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle(isOn: $draft.include) {
                    TextField("Name", text: $draft.name)
                        .textInputAutocapitalization(.words)
                        .font(.body.weight(.medium))
                }
                .toggleStyle(IncludeToggleStyle())
            }

            if draft.confidence.lowercased() == "low" {
                Label("Claude wasn't sure about this one", systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                TextField("Qty", value: $draft.quantity, format: .number)
                    .keyboardType(.decimalPad)
                    .frame(width: 60)
                    .textFieldStyle(.roundedBorder)

                Picker("Unit", selection: $draft.unit) {
                    ForEach(MeasureUnit.allCases) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
                .labelsHidden()

                Spacer()

                Picker("Category", selection: $draft.category) {
                    ForEach(FoodCategory.allCases) { category in
                        Text(category.displayName).tag(category)
                    }
                }
                .labelsHidden()
            }

            Toggle("Expiry date on the packaging", isOn: $draft.hasExpiry.animation())
                .font(.footnote)

            if draft.hasExpiry {
                DatePicker("Use by", selection: $draft.expiryDate, displayedComponents: .date)
                    .font(.footnote)
            } else {
                Text("Pantry will estimate a date when you save.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(draft.include ? 1 : 0.45)
        .padding(.vertical, 4)
    }
}

private struct IncludeToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            Button {
                configuration.isOn.toggle()
            } label: {
                Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(configuration.isOn ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            configuration.label
        }
    }
}

// MARK: - Camera

/// Minimal camera wrapper — `PhotosPicker` covers the library, but taking a
/// photo still needs UIKit.
struct CameraPicker: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, dismiss: { dismiss() })
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        let dismiss: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, dismiss: @escaping () -> Void) {
            self.onCapture = onCapture
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
