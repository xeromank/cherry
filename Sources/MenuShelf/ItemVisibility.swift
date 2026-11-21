import SwiftUI

@MainActor
struct ItemVisibilityView: View {
    let items: [StatusItem]
    let previouslyPinnedIDs: Set<String>
    let isScanning: Bool
    let refresh: () -> Void
    let openSystemSettings: () -> Void

    private var previousSelections: [StatusItem] {
        items.filter { previouslyPinnedIDs.contains($0.preferenceID) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                instructions
                if !previousSelections.isEmpty { priorSelections }
                HStack(spacing: 12) {
                    Button("macOS 메뉴 막대 설정 열기", action: openSystemSettings)
                        .buttonStyle(.bordered)
                    Spacer(minLength: 0)
                    if !previouslyPinnedIDs.isEmpty {
                        if isScanning {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel("이전 항목 확인 중")
                        } else {
                            Button("다시 확인", action: refresh)
                                .buttonStyle(.link)
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("⌘ 키를 누른 채 화면 상단의 원래 아이콘을 구분선(|) 양옆으로 드래그하세요.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Text("왼쪽에 두면 가려짐")
                    .frame(maxWidth: .infinity)
                Text("|")
                    .font(.system(.callout, design: .monospaced).weight(.medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("오른쪽에 두면 표시")
                    .frame(maxWidth: .infinity)
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
            Text("하단 바에서 아이콘을 우클릭한 뒤 ‘항상 표시’ 또는 ‘하단 바에만 표시’를 선택하세요.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var priorSelections: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("이전에 선택한 항목")
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(previousSelections) { item in
                    let title = item.title == item.appName ? item.title : "\(item.title) · \(item.appName)"
                    HStack(spacing: 6) {
                        Image(nsImage: item.appIcon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                            .accessibilityHidden(true)
                        Text(title)
                            .font(.caption)
                            .lineLimit(1)
                            .help(title)
                    }
                }
            }
        }
    }
}
