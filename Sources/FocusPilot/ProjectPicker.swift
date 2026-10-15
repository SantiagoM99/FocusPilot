import SwiftUI

/// Popup of existing projects plus "New project…", which reveals a name
/// field. Reports the chosen name, or nil for no project.
struct ProjectPicker: View {
    let projectTitles: [String]
    @Binding var projectName: String?

    private enum Choice: Hashable {
        case none
        case existing(String)
        case new
    }

    @State private var choice = Choice.none
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Project", selection: $choice) {
                Text("None").tag(Choice.none)
                ForEach(projectTitles, id: \.self) { Text($0).tag(Choice.existing($0)) }
                Divider()
                Text("New project…").tag(Choice.new)
            }
            .labelsHidden()
            .fixedSize()

            if choice == .new {
                TextField("Project name", text: $newName, prompt: Text("Project name"))
            }
        }
        .onChange(of: choice) { report() }
        .onChange(of: newName) { report() }
    }

    private func report() {
        switch choice {
        case .none: projectName = nil
        case .existing(let title): projectName = title
        case .new: projectName = newName
        }
    }
}
