import SwiftUI

struct SettingsView: View {
    let configurationManager: ConfigurationManager
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            Text("Settings - Coming Soon")
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                }
        }
    }
}