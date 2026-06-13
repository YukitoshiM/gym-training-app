import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Gym Training")
                            .font(.title2.bold())
                        Text("MVP environment scaffold")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Section("Next") {
                    Label("Create SwiftUI screens from the MVP design", systemImage: "doc.text")
                    Label("Add local-first data models", systemImage: "externaldrive")
                    Label("Prepare CloudKit sync", systemImage: "icloud")
                }
            }
            .navigationTitle("Home")
        }
    }
}

#Preview {
    HomeView()
}

