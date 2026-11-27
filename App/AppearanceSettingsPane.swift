import SwiftUI

struct AppearanceSettingsPane: View {
    @AppStorage(AppearancePreference.storageKey) private var appearance = AppearancePreference.automatic

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppearancePreference.allCases) { preference in
                    Text(preference.title).tag(preference)
                }
            }
            #if os(macOS)
            .pickerStyle(.radioGroup)
            #endif
        }
        #if os(macOS)
        .padding()
        .frame(width: 280)
        .onAppear {
            appearance.applyToApplication()
        }
        .onChange(of: appearance) { _, newValue in
            newValue.applyToApplication()
        }
        #endif
    }
}
