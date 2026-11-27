import SwiftUI

struct AppearanceSettingsPane: View {
    @AppStorage(AppearancePreference.storageKey) private var appearance = AppearancePreference.automatic
    #if os(macOS)
    @AppStorage(ExportAppearance.storageKey) private var exportAppearance = ExportAppearance.light
    #endif

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
            #if os(macOS)
            Picker("Export Appearance", selection: $exportAppearance) {
                ForEach(ExportAppearance.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .pickerStyle(.radioGroup)
            #endif
        }
        #if os(macOS)
        .padding()
        .frame(width: 360)
        .onAppear {
            appearance.applyToApplication()
        }
        .onChange(of: appearance) { _, newValue in
            newValue.applyToApplication()
        }
        #endif
    }
}
