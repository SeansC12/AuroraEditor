//
//  TabBar.swift
//  AuroraEditor
//
//  Created by Lukas Pistrol on 17.03.22.
//

import SwiftUI

// swiftlint:disable:next type_body_length
struct TabBar: View {
    /// The height of tab bar.
    /// I am not making it a private variable because it may need to be used in outside views.
    static let height = 28.0

    @Environment(\.colorScheme)
    private var colorScheme

    @Environment(\.controlActiveState)
    private var activeState

    private let windowController: NSWindowController

    @ObservedObject
    private var workspace: WorkspaceDocument

    @ObservedObject
    private var sourceControlModel: SourceControlModel

    @StateObject
    private var prefs: AppPreferencesModel = .shared

    // TabBar(windowController: windowController, workspace: workspace)
    init(windowController: NSWindowController, workspace: WorkspaceDocument) {
        self.windowController = windowController
        self.workspace = workspace
        self.sourceControlModel = workspace.workspaceClient?.model ?? .init(workspaceURL: workspace.fileURL!)
    }

    @State
    var expectedTabWidth: CGFloat = 0

    /// This state is used to detect if the mouse is hovering over tabs.
    /// If it is true, then we do not update the expected tab width immediately.
    @State
    var isHoveringOverTabs: Bool = false

    private func updateExpectedTabWidth(proxy: GeometryProxy) {
        expectedTabWidth = max(
            // Equally divided size of a native tab.
            (proxy.size.width + 1) / CGFloat(workspace.selectionState.openedTabs.count) + 1,
            // Min size of a native tab.
            CGFloat(140)
        )
    }

    /// Conditionally updates the `expectedTabWidth`.
    /// Called when the tab count changes or the temporary tab changes.
    /// - Parameter geometryProxy: The geometry proxy to calculate the new width using.
    private func updateForTabCountChange(geometryProxy: GeometryProxy) {
        // Only update the expected width when user is not hovering over tabs.
        // This should give users a better experience on closing multiple tabs continuously.
        if !isHoveringOverTabs {
            withAnimation(.easeOut(duration: 0.15)) {
                updateExpectedTabWidth(proxy: geometryProxy)
            }
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Tab bar navigation control.
            leadingAccessories
            // Tab bar items.
            GeometryReader { geometryProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    ScrollViewReader { scrollReader in
                        HStack(
                            alignment: .center,
                            spacing: -1
                        ) {
                            ForEach(workspace.selectionState.openedTabs, id: \.id) { id in
                                if let item = workspace.selectionState.getItemByTab(id: id) {
                                    TabBarItem(
                                        expectedWidth: $expectedTabWidth,
                                        item: item,
                                        windowController: windowController,
                                        workspace: workspace
                                    )
                                    .frame(height: TabBar.height)
                                }
                            }
                        }
                        // This padding is to hide dividers at two ends under the accessory view divider.
                        .padding(.horizontal, prefs.preferences.general.tabBarStyle == .native ? -1 : 0)
                        .onAppear {
                            // On view appeared, compute the initial expected width for tabs.
                            updateExpectedTabWidth(proxy: geometryProxy)
                            // On first tab appeared, jump to the corresponding position.
                            scrollReader.scrollTo(workspace.selectionState.selectedId)
                        }
                        // When selected tab is changed, scroll to it if possible.
                        .onChange(of: workspace.selectionState.selectedId) { targetId in
                            guard let selectedId = targetId else { return }
                            scrollReader.scrollTo(selectedId)
                        }
                        // When tabs are changing, re-compute the expected tab width.
                        .onChange(of: workspace.selectionState.openedTabs.count) { _ in
                            updateForTabCountChange(geometryProxy: geometryProxy)
                        }
                        .onChange(of: workspace.selectionState.temporaryTab, perform: { _ in
                            updateForTabCountChange(geometryProxy: geometryProxy)
                        })
                        // When window size changes, re-compute the expected tab width.
                        .onChange(of: geometryProxy.size.width) { _ in
                            updateExpectedTabWidth(proxy: geometryProxy)
                        }
                        // When user is not hovering anymore, re-compute the expected tab width immediately.
                        .onHover { isHovering in
                            isHoveringOverTabs = isHovering
                            if !isHovering {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    updateExpectedTabWidth(proxy: geometryProxy)
                                }
                            }
                        }
                        .frame(height: TabBar.height)
                    }
                }
                // When there is no opened file, hide the scroll view, but keep the background.
                .opacity(
                    workspace.selectionState.openedTabs.isEmpty && workspace.selectionState.temporaryTab == nil
                    ? 0.0
                    : 1.0
                )
                // To fill up the parent space of tab bar.
                .frame(maxWidth: .infinity)
                .background {
                    if prefs.preferences.general.tabBarStyle == .native {
                        TabBarNativeInactiveBackground()
                    }
                }
            }
            // Tab bar tools (e.g. split view).
            trailingAccessories
        }
        .frame(height: TabBar.height)
        .overlay(alignment: .top) {
            // When tab bar style is `xcode`, we put the top divider as an overlay.
            if prefs.preferences.general.tabBarStyle == .xcode {
                TabBarTopDivider()
            }
        }
        .background {
            if prefs.preferences.general.tabBarStyle == .xcode {
                TabBarXcodeBackground()
            }
        }
        .background {
            if prefs.preferences.general.tabBarStyle == .xcode {
                EffectView(
                    NSVisualEffectView.Material.titlebar,
                    blendingMode: NSVisualEffectView.BlendingMode.withinWindow
                )
                // Set bottom padding to avoid material overlapping in bar.
                .padding(.bottom, TabBar.height)
                .edgesIgnoringSafeArea(.top)
            } else {
                TabBarNativeMaterial()
                    .edgesIgnoringSafeArea(.top)
            }
        }
        .padding(.leading, -1)
    }

    // MARK: Accessories
    // TabBar items on the left
    private var leadingAccessories: some View {
        HStack(spacing: 2) {
            recentMenuButton
                .help("Navigate to Related Items")

            Divider()
                .padding(.vertical, 8)

            TabBarAccessoryIcon(
                icon: .init(systemName: "chevron.left"),
                action: {
                    let currentTab = workspace.selectionState.selectedId

                    guard let idx = workspace.selectionState.openedTabs.firstIndex(of: currentTab!) else { return }

                    if workspace.selectionState.selectedId == currentTab {
                        workspace.selectionState.selectedId = workspace.selectionState.openedTabs[idx - 1]
                    }
                }
            )
            .font(Font.system(size: 14, weight: .light, design: .default))
            .foregroundColor(.secondary)
            .disabled(workspace.selectionState.openedTabs.isEmpty || disableTabNavigationLeft())
            .buttonStyle(.plain)
            .help("Navigate back")

            TabBarAccessoryIcon(
                icon: .init(systemName: "chevron.right"),
                action: {
                    let currentTab = workspace.selectionState.selectedId

                    guard let idx = workspace.selectionState.openedTabs.firstIndex(of: currentTab!) else { return }

                    if workspace.selectionState.selectedId == currentTab {
                        workspace.selectionState.selectedId = workspace.selectionState.openedTabs[idx + 1]
                    }
                }
            )
            .font(Font.system(size: 14, weight: .light, design: .default))
            .foregroundColor(.secondary)
            .disabled(workspace.selectionState.openedTabs.isEmpty || disableTabNavigationRight())
            .buttonStyle(.plain)
            .help("Navigate forward")
        }
        .padding(.horizontal, 7)
        .opacity(activeState != .inactive ? 1.0 : 0.5)
        .frame(maxHeight: .infinity) // Fill out vertical spaces.
        .background {
            if prefs.preferences.general.tabBarStyle == .native {
                TabBarAccessoryNativeBackground(dividerAt: .trailing)
            }
        }
    }

    // TabBar items on right
    private var trailingAccessories: some View {
        HStack(spacing: 2) {
            if !workspace.selectionState.openFileItems.isEmpty {
                TabBarAccessoryIcon(
                    icon: .init(systemName: "arrow.left.arrow.right"),
                    action: {
                    }
                )
                .font(Font.system(size: 10, weight: .light, design: .default))
                .foregroundColor(.secondary)
                .buttonStyle(.plain)
                .disabled(!prefs.sourceControlActive())
                .help("Enable Code Review")

                TabBarAccessoryIcon(
                    icon: .init(systemName: "ellipsis.circle"),
                    action: { /* TODO */ }
                )
                .font(Font.system(size: 14, weight: .light, design: .default))
                .foregroundColor(.secondary)
                .buttonStyle(.plain)
                .help("Options")

                Divider()
                    .padding(.vertical, 8)
            }

            ToolbarPlusMenu(workspace: workspace)
                .foregroundColor(.secondary)
                .help("Open New Web Tab")

            TabBarAccessoryIcon(
                icon: .init(systemName: "square.split.2x1"),
                action: { /* TODO */ }
            )
            .font(Font.system(size: 14, weight: .light, design: .default))
            .foregroundColor(.secondary)
            .buttonStyle(.plain)
            .help("Split View")
        }
        .padding(.horizontal, 7)
        .opacity(activeState != .inactive ? 1.0 : 0.5)
        .frame(maxHeight: .infinity) // Fill out vertical spaces.
        .background {
            if prefs.preferences.general.tabBarStyle == .native {
                TabBarAccessoryNativeBackground(dividerAt: .leading)
            }
        }
    }

    // If the currently selected tab is the first item in
    // the list we disable the left navigation button otherwise
    // if it's > 0 we enable it.
    private func disableTabNavigationLeft() -> Bool {
        let openedTabs = workspace.selectionState.openedTabs
        let currentTab = workspace.selectionState.selectedId
        let tabPosition = openedTabs.firstIndex {
            $0 == currentTab
        }

        if tabPosition == 0 {
            return true
        }

        return false
    }

    // Disables the right navigation button when the current tab
    // is the last item in the list, if the current item is not the
    // last item we re-enable it allowing the user to navigate forward
    // of any open tabs they may have.
    private func disableTabNavigationRight() -> Bool {
        let openedTabs = workspace.selectionState.openedTabs
        let currentTab = workspace.selectionState.selectedId

        if currentTab == openedTabs.last {
            return true
        }

        return false
    }

    private var recentMenuButton: some View {
        VStack {
            if #available(macOS 13, *) {
                Menu {
                    Menu {
                        ForEach(sourceControlModel.changed) { item in
                            Button {

                            } label: {
                                Image(systemName: item.systemImage)
                                    .foregroundColor(item.iconColor)
                                Text(item.fileName)
                            }
                        }
                        Divider()
                        Button {
                        } label: {
                            Text("Clear Menu")
                        }
                    } label: {
                        Text("Recent Files")
                    }

                    Menu {
                        ForEach(sourceControlModel.changed) { item in
                            Button {
                                workspace.openTab(item: item)
                            } label: {
                                Image(systemName: item.systemImage)
                                    .foregroundColor(item.iconColor)
                                Text(item.fileName)
                            }
                        }
                    } label: {
                        Text("Locally Modified Files")
                    }
                } label: {
                    Image(systemName: "square.grid.2x2")
                }
                .buttonStyle(.plain)
            } else {
                Menu {
                    Menu {
                        ForEach(sourceControlModel.changed) { item in
                            Button {

                            } label: {
                                Image(systemName: item.systemImage)
                                    .foregroundColor(item.iconColor)
                                Text(item.fileName)
                            }
                        }
                        Divider()
                        Button {
                        } label: {
                            Text("Clear Menu")
                        }
                    } label: {
                        Text("Recent Files")
                    }

                    Menu {
                        ForEach(sourceControlModel.changed) { item in
                            Button {
                                workspace.openTab(item: item)
                            } label: {
                                Image(systemName: item.systemImage)
                                    .foregroundColor(item.iconColor)
                                Text(item.fileName)
                            }
                        }
                    } label: {
                        Text("Locally Modified Files")
                    }
                } label: {
                    Image(systemName: "square.grid.2x2")
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .frame(width: 20)
            }
        }
    }
}
