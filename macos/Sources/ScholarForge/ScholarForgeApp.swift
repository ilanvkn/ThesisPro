import SwiftUI

@main
struct ScholarForgeApp: App {
    @State private var store = ProjectStore()
    @AppStorage("thesisplus.appearance") private var appearance = "Light"
    private var colorScheme: ColorScheme? { appearance == "Light" ? .light : appearance == "Dark" ? .dark : nil }

    var body: some Scene {
        WindowGroup("ThesisPro") {
            RootView().environment(store)
                .preferredColorScheme(colorScheme)
                .tint(Color(red: 0.23, green: 0.39, blue: 0.48))
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .saveItem) {
                Button("Save Project") { store.save() }.keyboardShortcut("s", modifiers: .command)
            }
            SidebarCommands(); ToolbarCommands()
        }

        Settings { SettingsView().environment(store).preferredColorScheme(colorScheme) }
    }
}

struct SettingsView: View {
    @Environment(ProjectStore.self) private var store
    var body: some View {
        WorkspacePreferences()
    }
}
