import SwiftUI

struct SettingsMenuOption<Value: Hashable>: Identifiable {
    let id: Value
    let title: String
}

@MainActor
struct SettingsMenuPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [SettingsMenuOption<Value>]
    let maxWidth: CGFloat?
    let controlSize: ControlSize

    init(
        _ title: String,
        selection: Binding<Value>,
        options: [SettingsMenuOption<Value>],
        maxWidth: CGFloat? = 200,
        controlSize: ControlSize = .regular)
    {
        self.title = title
        self._selection = selection
        self.options = options
        self.maxWidth = maxWidth
        self.controlSize = controlSize
    }

    var body: some View {
        Menu {
            ForEach(self.options) { option in
                Button {
                    self.selection = option.id
                } label: {
                    HStack {
                        Text(option.title)
                        Spacer()
                        if option.id == self.selection {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(Self.selectedTitle(selection: self.selection, options: self.options))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: self.maxWidth, alignment: .trailing)
        }
        .accessibilityLabel(self.title)
        .controlSize(self.controlSize)
    }

    static func selectedTitle(selection: Value, options: [SettingsMenuOption<Value>]) -> String {
        options.first { $0.id == selection }?.title ?? ""
    }
}
