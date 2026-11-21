import SwiftUI

struct ShelfRibbon: View {
    let items: [StatusItem]
    let isScanning: Bool
    let isPinning: Bool
    let feedback: String?
    let choose: (StatusItem) -> Void
    let setPlacement: (StatusItem, StatusItemPlacement) -> Void
    let openSettings: () -> Void
    let close: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var hoveredItemID: StatusItem.ID?

    private let shape = RoundedRectangle(cornerRadius: 16)
    private let accent = Color(nsColor: .systemTeal)

    var body: some View {
        VStack(spacing: 3) {
            controls
            if let feedback {
                Text(feedback)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)
                    .help(feedback)
            }
        }
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if reduceTransparency {
                shape.fill(Color(nsColor: .windowBackgroundColor))
            } else {
                shape.fill(.regularMaterial)
            }
        }
        .overlay { shape.strokeBorder(.primary.opacity(0.14)).allowsHitTesting(false) }
        .clipShape(shape)
    }

    private var controls: some View {
        HStack(spacing: 9) {
            itemStrip

            if isScanning && !items.isEmpty { scanningIndicator }

            Divider()
                .frame(height: 25)
                .accessibilityHidden(true)

            Button(action: openSettings) {
                controlIcon("gearshape")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("설정")
            .help("설정")

            Button(action: close) {
                controlIcon("xmark")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("닫기")
            .help("닫기 (Esc)")
        }
    }

    @ViewBuilder
    private var itemStrip: some View {
        if items.isEmpty {
            HStack(spacing: 7) {
                if isScanning { scanningIndicator.accessibilityHidden(true) }
                Text(isScanning ? "메뉴 막대 확인 중…" : "표시할 메뉴 막대 항목이 없어요")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.leading, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 5) {
                    ForEach(items) { item in itemButton(item) }
                }
                .padding(.horizontal, 3)
                .frame(height: 44)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .scrollIndicators(.visible, axes: .horizontal)
            .frame(height: 51)
            .accessibilityLabel("메뉴 막대 항목")
        }
    }

    private var scanningIndicator: some View {
        ProgressView()
            .controlSize(.small)
            .accessibilityLabel("메뉴 막대 확인 중")
    }

    private func itemButton(_ item: StatusItem) -> some View {
        let label = item.title == item.appName ? item.title : "\(item.title) · \(item.appName)"
        let tile = RoundedRectangle(cornerRadius: 10)
        return Button {
            choose(item)
        } label: {
            Image(nsImage: item.appIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 25, height: 25)
                .frame(width: 39, height: 39)
                .background(hoveredItemID == item.id ? accent.opacity(0.2) : .primary.opacity(0.065), in: tile)
                .overlay(alignment: .topTrailing) {
                    if item.isHidden {
                        Circle()
                            .fill(accent)
                            .frame(width: 5, height: 5)
                            .padding(5)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(tile)
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            if isHovering {
                hoveredItemID = item.id
            } else if hoveredItemID == item.id {
                hoveredItemID = nil
            }
        }
        .accessibilityLabel(label)
        .accessibilityValue(item.isHidden ? "가려짐" : "표시 중")
        .contextMenu {
            placementButtons(for: item)
        }
        .accessibilityActions {
            if !isPinning {
                placementButtons(for: item)
            }
        }
        .help(item.isHidden ? "\(label) · 가려짐" : label)
    }

    @ViewBuilder
    private func placementButtons(for item: StatusItem) -> some View {
        Button("항상 표시") { setPlacement(item, .visible) }
            .disabled(isPinning)
        Button("하단 바에만 표시") { setPlacement(item, .hidden) }
            .disabled(isPinning)
    }

    private func controlIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 25, height: 29)
            .contentShape(Rectangle())
    }
}
