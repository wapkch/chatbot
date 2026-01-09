import SwiftUI

struct ConfigurationListView: View {
    @ObservedObject var configurationManager: ConfigurationManager
    @Environment(\.presentationMode) var presentationMode

    // UI State
    @State private var showingAddConfiguration = false
    @State private var showingEditConfiguration = false
    @State private var configurationToEdit: APIConfiguration?
    @State private var configurationToDelete: APIConfiguration?
    @State private var showingDeleteAlert = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationView {
            List {
                if configurationManager.configurations.isEmpty {
                    EmptyStateView()
                } else {
                    ForEach(configurationManager.configurations) { configuration in
                        ConfigurationRowView(
                            configuration: configuration,
                            isActive: configurationManager.activeConfiguration?.id == configuration.id,
                            onSelect: { selectConfiguration(configuration) },
                            onEdit: { editConfiguration(configuration) },
                            onDelete: { deleteConfiguration(configuration) }
                        )
                    }
                }
            }
            .navigationTitle("API Configurations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddConfiguration = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddConfiguration) {
                ConfigurationEditView(configurationManager: configurationManager)
            }
            .sheet(isPresented: $showingEditConfiguration) {
                if let config = configurationToEdit {
                    ConfigurationEditView(
                        configurationManager: configurationManager,
                        configuration: config
                    )
                }
            }
            .alert("Delete Configuration", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    confirmDelete()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let config = configurationToDelete {
                    Text("Are you sure you want to delete '\(config.name)'? This action cannot be undone.")
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func selectConfiguration(_ configuration: APIConfiguration) {
        Task {
            do {
                try await configurationManager.setActiveConfiguration(configuration)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func editConfiguration(_ configuration: APIConfiguration) {
        configurationToEdit = configuration
        showingEditConfiguration = true
    }

    private func deleteConfiguration(_ configuration: APIConfiguration) {
        configurationToDelete = configuration
        showingDeleteAlert = true
    }

    private func confirmDelete() {
        guard let config = configurationToDelete else { return }

        Task {
            do {
                try await configurationManager.deleteConfiguration(config)
                await MainActor.run {
                    configurationToDelete = nil
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    configurationToDelete = nil
                }
            }
        }
    }
}

// MARK: - Configuration Row View
struct ConfigurationRowView: View {
    let configuration: APIConfiguration
    let isActive: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(configuration.name)
                            .font(.headline)
                            .foregroundColor(.primary)

                        if configuration.isDefault {
                            Text("DEFAULT")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .foregroundColor(.blue)
                                .clipShape(Capsule())
                        }

                        Spacer()

                        if isActive {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Button("Select") {
                                onSelect()
                            }
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .clipShape(Capsule())
                        }
                    }

                    Text("Model: \(configuration.modelID)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text(configuration.baseURL)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()
            }
            .contentShape(Rectangle())

            // Action buttons
            HStack {
                Spacer()

                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                        .font(.caption)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: onDelete) {
                    Label("Delete", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.red)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Empty State View
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "gear.circle")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("No Configurations")
                    .font(.headline)
                    .foregroundColor(.primary)

                Text("Add your first API configuration to get started with ChatMe.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

// MARK: - Preview
struct ConfigurationListView_Previews: PreviewProvider {
    static var previews: some View {
        let manager = ConfigurationManager()

        Group {
            ConfigurationListView(configurationManager: manager)
                .previewDisplayName("With Configurations")

            ConfigurationListView(configurationManager: ConfigurationManager())
                .previewDisplayName("Empty State")
        }
    }
}