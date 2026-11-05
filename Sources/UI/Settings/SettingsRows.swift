import SwiftUI

/// A titled, rounded group of settings rows.
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
        }
    }
}

struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .pointingHandCursor()
        }
    }
}

/// A title (with an optional hint underneath) and a picker on the right.
struct SettingsPickerRow<Option: Hashable, Options: RandomAccessCollection>: View where Options.Element == Option {
    let title: String
    var hint: String?
    @Binding var selection: Option
    let options: Options
    var segmented = false
    let label: (Option) -> String

    var body: some View {
        HStack {
            SettingsRowTitle(title: title, hint: hint)
            Spacer()
            picker
                .labelsHidden()
                .fixedSize()
                .pointingHandCursor()
        }
    }

    @ViewBuilder
    private var picker: some View {
        let picker = Picker(title, selection: $selection) {
            ForEach(Array(options), id: \.self) { option in
                Text(label(option)).tag(option)
            }
        }
        if segmented {
            picker.pickerStyle(.segmented)
        } else {
            picker.pickerStyle(.menu)
        }
    }
}

/// A setting's name, with a smaller hint underneath when there is one.
struct SettingsRowTitle: View {
    let title: String
    var hint: String?

    var body: some View {
        if let hint {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(title)
        }
    }
}
