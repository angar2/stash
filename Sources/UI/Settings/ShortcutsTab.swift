// 설정 단축키 탭 — settings.jsx S_Shortcuts L182-278 정합
// 변경 가능 10항 (CHANGEABLE_SHORTCUTS) — KeyboardShortcuts SPM Recorder. 변경 불가 단축키는 표 안 노출 X (plan F-008 정합)
import SwiftUI
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let paste = Self("stash.paste")
    static let pinToggle = Self("stash.pinToggle")
    static let deleteOne = Self("stash.deleteOne")
    static let deleteAll = Self("stash.deleteAll")
    static let deleteAllAlias = Self("stash.deleteAllAlias")
    static let cursorUpNum = Self("stash.cursorUpNum")
    static let cursorDownNum = Self("stash.cursorDownNum")
}

struct ShortcutsTab: View {
    @Bindable var viewModel: SettingsViewModel

    private struct ShortcutRow: Identifiable {
        let id: String
        let name: KeyboardShortcuts.Name
        let labelKey: String
    }

    private let rows: [ShortcutRow] = [
        .init(id: "cursorUpNum", name: .cursorUpNum, labelKey: "shortcuts.cursor.upNum"),
        .init(id: "cursorDownNum", name: .cursorDownNum, labelKey: "shortcuts.cursor.downNum"),
        .init(id: "paste", name: .paste, labelKey: "shortcuts.paste"),
        .init(id: "pinToggle", name: .pinToggle, labelKey: "shortcuts.pinToggle"),
        .init(id: "deleteOne", name: .deleteOne, labelKey: "shortcuts.deleteOne"),
        .init(id: "deleteAll", name: .deleteAll, labelKey: "shortcuts.deleteAll"),
        .init(id: "deleteAllAlias", name: .deleteAllAlias, labelKey: "shortcuts.deleteAllAlias")
    ]

    var body: some View {
        VStack(spacing: 14) {
            settingsCard {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                        shortcutRow(row: row)
                        if idx < rows.count - 1 {
                            Divider().foregroundStyle(DesignTokens.Colors.settingsRowDivider)
                        }
                    }
                }
            }

            HStack {
                if let msg = viewModel.shortcutConflictMessage {
                    Text(msg)
                        .font(DesignTokens.Typography.settingsCaption)
                        .foregroundStyle(DesignTokens.Colors.toastError)
                }
                Spacer()
                Button(action: {
                    KeyboardShortcuts.reset(rows.map { $0.name })
                }) {
                    Text(String(localized: "shortcuts.resetAll"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DesignTokens.Colors.labelPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.settingsButton, style: .continuous)
                                .fill(DesignTokens.Colors.settingsCardBg)
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignTokens.Radius.settingsButton, style: .continuous)
                                        .stroke(DesignTokens.Colors.divider, lineWidth: 0.5)
                                )
                        )
                }
                .buttonStyle(.plain)
            }

            Text(String(localized: "shortcuts.note"))
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(DesignTokens.Colors.labelSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private func shortcutRow(row: ShortcutRow) -> some View {
        HStack(alignment: .center) {
            Text(String(localized: String.LocalizationValue(row.labelKey)))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.labelPrimary)
            Spacer()
            KeyboardShortcuts.Recorder(for: row.name)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}
