import SwiftUI

struct ShelfView: View {
    @ObservedObject var model: ShelfModel
    var close: () -> Void
    var choose: (StatusItem) -> Void
    var requestPermission: () -> Void
    var openSettings: () -> Void
    var openPreferences: () -> Void
    var openMenuBarSettings: () -> Void
    var refresh: () -> Void
    var quit: () -> Void

    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let accent = Color(nsColor: .systemTeal)

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.isTrusted {
                searchField
                scopePicker
                if let feedback = model.feedback { failureBanner(feedback) }
                results
            } else {
                permissionView
            }
            Divider().padding(.horizontal, 18)
            footer
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.primary.opacity(0.12)))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .onChange(of: model.focusRequest) { _, _ in
            if model.isTrusted { searchFocused = true }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 34, height: 34)
                .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            Text("Cherry")
                .font(.system(size: 19, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("닫기")
            .help("닫기 (Esc)")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("메뉴 막대 항목 검색", text: $model.query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit { if let item = model.selectedItem { choose(item) } }
                .onChange(of: model.query) { _, _ in model.reconcileSelection() }
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("검색어 지우기")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(accent.opacity(searchFocused ? 0.65 : 0)))
        .padding(.horizontal, 18)
    }

    private var scopePicker: some View {
        HStack(spacing: 6) {
            ForEach(ShelfScope.allCases, id: \.self) { scope in
                Button {
                    changeScope(to: scope)
                } label: {
                    Text(scope.title)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .frame(height: 25)
                        .background(model.scope == scope ? accent.opacity(0.2) : .clear, in: Capsule())
                        .foregroundStyle(model.scope == scope ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.scope == scope ? [.isSelected] : [])
            }
            Spacer()
            if model.isScanning {
                ProgressView().controlSize(.small)
                    .accessibilityLabel("메뉴 막대 항목 검색 중")
            } else {
                Text("\(model.results.count)개")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11).monospacedDigit())
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }

    @ViewBuilder
    private var results: some View {
        if model.results.isEmpty {
            emptyView
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(model.results) { item in
                            itemRow(item)
                        }
                    }
                    .padding(.horizontal, 13)
                    .padding(.bottom, 9)
                }
                .onChange(of: model.selectedID) { _, id in
                    if let id {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { proxy.scrollTo(id) }
                    }
                }
            }
        }
    }

    private func itemRow(_ item: StatusItem) -> some View {
        let selected = item.id == model.selectedID
        return Button { choose(item) } label: {
            HStack(spacing: 10) {
                Image(nsImage: item.appIcon)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if item.title != item.appName {
                        Text(item.appName)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if item.isHidden {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("가려짐")
                }
                Image(systemName: "return")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .opacity(selected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .frame(height: 43)
            .background(selected ? accent.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .id(item.id)
    }

    private var emptyView: some View {
        VStack(spacing: 9) {
            if model.isScanning {
                Text("메뉴 막대 확인 중…")
            } else if !model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Image(systemName: "magnifyingglass").font(.system(size: 22))
                Text("검색 결과가 없어요")
                if model.scope == .hidden {
                    Button("전체 항목에서 검색") { changeScope(to: .all) }
                }
            } else if model.scope == .hidden {
                Image(systemName: "eye").font(.system(size: 22))
                Text("가려진 항목을 찾지 못했어요")
                Button("전체 항목 보기") { changeScope(to: .all) }
            } else {
                Image(systemName: "menubar.rectangle").font(.system(size: 22))
                Text("표시할 메뉴 막대 항목이 없어요")
                Button("다시 검색", action: refresh)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 18)
    }

    private var permissionView: some View {
        VStack(alignment: .leading, spacing: 11) {
            Image(systemName: "accessibility")
                .font(.system(size: 27, weight: .medium))
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            Text("손쉬운 사용 권한이 필요해요")
                .font(.system(size: 19, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text("다른 앱의 메뉴 막대 항목을 찾고 선택한 메뉴를 열려면 시스템 설정에서 Cherry를 허용해 주세요.")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("권한 요청", action: requestPermission)
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                Button("손쉬운 사용 설정", action: openSettings)
                    .buttonStyle(.bordered)
            }
            .padding(.top, 6)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 18)
        .frame(maxHeight: .infinity)
    }

    private func failureBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(message)
                .font(.system(size: 12))
            Button("메뉴 막대 설정 열기", action: openMenuBarSettings)
                .buttonStyle(.link)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.17), in: RoundedRectangle(cornerRadius: 9))
        .padding(.horizontal, 18)
        .padding(.bottom, 6)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if model.isTrusted {
                Text("↑↓ 이동")
                Text("↩ 열기")
            }
            if model.hotKeyAvailable {
                Text("⌃⇧Space 호출")
            }
            Spacer()
            Menu {
                Button("다시 검색", action: refresh).disabled(!model.isTrusted || model.isScanning)
                Button("Cherry 설정", action: openPreferences)
                Button("메뉴 막대 설정", action: openMenuBarSettings)
                Divider()
                Button("Cherry 종료", action: quit)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15))
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("추가 작업")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .frame(height: 37)
        .padding(.horizontal, 18)
    }

    private func changeScope(to scope: ShelfScope) {
        model.scope = scope
        model.reconcileSelection()
        searchFocused = true
    }
}
