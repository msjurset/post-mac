import SwiftUI

public struct EnvironmentManagerSheet: View {
    @ObservedObject var store: PostStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: ManagerTab = .environments
    @State private var selectedEnvID: UUID?

    public init(store: PostStore) {
        self.store = store
        _selectedEnvID = State(initialValue: store.selectedEnvironmentID ?? store.environments.first?.id)
    }

    public enum ManagerTab: String, CaseIterable, Identifiable {
        case environments = "Environments & Secrets"
        case collections = "Request Collections"

        public var id: String { rawValue }
    }

    public var body: some View {
        VStack(spacing: 0) {
            topTabBar
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            Divider()

            Group {
                switch selectedTab {
                case .environments:
                    environmentsSplitView
                case .collections:
                    collectionsView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            bottomBar
                .padding(14)
        }
        .frame(minWidth: 720, idealWidth: 760, minHeight: 480, idealHeight: 520)
        .onAppear {
            if selectedEnvID == nil || !store.environments.contains(where: { $0.id == selectedEnvID }) {
                selectedEnvID = store.selectedEnvironmentID ?? store.environments.first?.id
            }
        }
    }

    private var topTabBar: some View {
        HStack {
            Picker("", selection: $selectedTab) {
                ForEach(ManagerTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)

            Spacer()

            if selectedTab == .environments {
                Button(action: addEnvironment) {
                    Label("Add Environment", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .focusable(false)
            } else {
                Button(action: addCollection) {
                    Label("Add Collection", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .focusable(false)
            }
        }
    }

    private var environmentsSplitView: some View {
        HStack(spacing: 0) {
            environmentSidebar
                .frame(width: 220)

            Divider()

            if let envIndex = store.environments.firstIndex(where: { $0.id == selectedEnvID }) {
                environmentDetailView(envIndex: envIndex)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("Select or create an environment")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var environmentSidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedEnvID) {
                ForEach(store.environments) { env in
                    HStack(spacing: 8) {
                        Button(action: {
                            store.selectedEnvironmentID = env.id
                            selectedEnvID = env.id
                            store.saveToDisk()
                        }) {
                            Image(systemName: store.selectedEnvironmentID == env.id ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(store.selectedEnvironmentID == env.id ? Color.green : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .help(store.selectedEnvironmentID == env.id ? "Active Environment" : "Click to make active")

                        VStack(alignment: .leading, spacing: 2) {
                            Text(env.name)
                                .font(.body)
                                .lineLimit(1)
                            Text("\(env.variables.count) variables")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if store.environments.count > 1 {
                            Button(action: {
                                deleteEnvironment(id: env.id)
                            }) {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedEnvID = env.id
                    }
                    .tag(env.id)
                }
            }
            .listStyle(.sidebar)
        }
    }

    private func environmentDetailView(envIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Environment Name")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    FilterField(
                        placeholder: "Environment Name",
                        text: $store.environments[envIndex].name
                    )
                    .frame(width: 240)
                }

                Spacer()

                if store.selectedEnvironmentID == store.environments[envIndex].id {
                    Label("Active Environment", systemImage: "checkmark.seal.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.green.opacity(0.12), in: Capsule())
                } else {
                    Button(action: {
                        store.selectedEnvironmentID = store.environments[envIndex].id
                        store.saveToDisk()
                    }) {
                        Label("Make Active", systemImage: "bolt.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .focusable(false)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            Divider()

            HStack(spacing: 8) {
                Text("Variables (Interpolate via {{key}} or op://Vault/Item/field)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: {
                    KeychainHelper.shared.clearOnePasswordCache()
                }) {
                    Label("Clear 1P Cache", systemImage: "key.radiowaves.forward")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .focusable(false)
                .help("Clear cached 1Password (op://) secrets for this session")

                Button(action: {
                    addVariable(to: envIndex)
                }) {
                    Label("Add Variable", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .focusable(false)
            }
            .padding(.horizontal, 16)

            if store.environments[envIndex].variables.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "curlybraces")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("No variables in this environment")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Variables can be referenced in URLs, headers, and request bodies using {{variable_name}} or 1Password op://Vault/Item/field URIs.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach($store.environments[envIndex].variables) { $variable in
                            variableRow(variable: $variable, envIndex: envIndex)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private func variableRow(variable: Binding<EnvironmentVariable>, envIndex: Int) -> some View {
        let is1PRef = KeychainHelper.isOnePasswordReference(variable.wrappedValue.value)

        return HStack(spacing: 8) {
            Toggle("", isOn: variable.isEnabled)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .help("Enable or disable this variable")

            FilterField(
                placeholder: "KEY",
                text: variable.key
            )
            .frame(width: 140)

            FilterField(
                placeholder: variable.wrappedValue.isSecret ? "Secret (Keychain)" : "VALUE or op://Vault/Item/field",
                text: Binding(
                    get: {
                        if variable.wrappedValue.isSecret {
                            return KeychainHelper.shared.getSecret(forKey: variable.wrappedValue.key) ?? variable.wrappedValue.value
                        }
                        return variable.wrappedValue.value
                    },
                    set: { newVal in
                        if variable.wrappedValue.isSecret {
                            KeychainHelper.shared.setSecret(newVal, forKey: variable.wrappedValue.key)
                        }
                        variable.wrappedValue.value = newVal
                    }
                )
            )

            if is1PRef {
                HStack(spacing: 3) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 9))
                    Text("1P op://")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(.blue)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.blue.opacity(0.14), in: Capsule())
                .help("Resolved on-demand via 1Password CLI (`op read`) with Touch ID & session cache")
            }

            Button(action: {
                variable.wrappedValue.isSecret.toggle()
                let currentVal = variable.wrappedValue.value
                if variable.wrappedValue.isSecret {
                    if !currentVal.isEmpty && !variable.wrappedValue.key.isEmpty {
                        KeychainHelper.shared.setSecret(currentVal, forKey: variable.wrappedValue.key)
                    }
                } else {
                    if !variable.wrappedValue.key.isEmpty {
                        KeychainHelper.shared.deleteSecret(forKey: variable.wrappedValue.key)
                    }
                }
                store.saveToDisk()
            }) {
                Image(systemName: variable.wrappedValue.isSecret ? "lock.fill" : "lock.open")
                    .foregroundStyle(variable.wrappedValue.isSecret ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(variable.wrappedValue.isSecret ? "Secret stored in Keychain" : "Plain text (click to protect with Keychain)")

            Button(action: {
                if variable.wrappedValue.isSecret && !variable.wrappedValue.key.isEmpty {
                    KeychainHelper.shared.deleteSecret(forKey: variable.wrappedValue.key)
                }
                store.environments[envIndex].variables.removeAll(where: { $0.id == variable.wrappedValue.id })
                store.saveToDisk()
            }) {
                Image(systemName: "trash")
                    .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Delete variable")
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
    }

    private var collectionsView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Organize Requests into Collections")
                    .font(.headline)
                Spacer()
                Text("\(store.collections.count) collections")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            Divider()

            if store.collections.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No collections defined")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Create First Collection", action: addCollection)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .focusable(false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach($store.collections) { $col in
                            collectionRow(collection: $col)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private func collectionRow(collection: Binding<RequestCollection>) -> some View {
        let requestCount = store.requests.filter { $0.collectionId == collection.wrappedValue.id }.count

        return HStack(spacing: 10) {
            Menu {
                ForEach(["folder", "tray", "archivebox", "tag", "bolt", "star", "bookmark", "globe", "network"], id: \.self) { icon in
                    Button(action: {
                        collection.wrappedValue.iconName = icon
                        store.saveToDisk()
                    }) {
                        Label(icon, systemImage: icon)
                    }
                    .focusable(false)
                }
            } label: {
                Image(systemName: collection.wrappedValue.iconName)
                    .font(.system(size: 14))
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .focusable(false)
            .frame(width: 28)

            FilterField(
                placeholder: "Collection Name",
                text: collection.name
            )

            Text("\(requestCount) requests")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)

            Button(action: {
                deleteCollection(id: collection.wrappedValue.id)
            }) {
                Image(systemName: "trash")
                    .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Delete collection")
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
    }

    private var bottomBar: some View {
        HStack {
            if let active = store.activeEnvironment {
                Label("Active: \(active.name)", systemImage: "bolt.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No active environment")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Done") {
                store.saveToDisk()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .focusable(false)
        }
    }

    private func addEnvironment() {
        let newEnv = PostEnvironment(
            name: "Environment \(store.environments.count + 1)",
            variables: []
        )
        store.environments.append(newEnv)
        selectedEnvID = newEnv.id
        if store.selectedEnvironmentID == nil {
            store.selectedEnvironmentID = newEnv.id
        }
        store.saveToDisk()
    }

    private func deleteEnvironment(id: UUID) {
        store.environments.removeAll(where: { $0.id == id })
        if store.selectedEnvironmentID == id {
            store.selectedEnvironmentID = store.environments.first?.id
        }
        if selectedEnvID == id {
            selectedEnvID = store.environments.first?.id
        }
        store.saveToDisk()
    }

    private func addVariable(to envIndex: Int) {
        guard envIndex < store.environments.count else { return }
        let newVar = EnvironmentVariable(key: "new_var", value: "", isSecret: false, isEnabled: true)
        store.environments[envIndex].variables.append(newVar)
        store.saveToDisk()
    }

    private func addCollection() {
        let newCol = RequestCollection(
            name: "Collection \(store.collections.count + 1)",
            iconName: "folder"
        )
        store.collections.append(newCol)
        store.saveToDisk()
    }

    private func deleteCollection(id: UUID) {
        store.collections.removeAll(where: { $0.id == id })
        for i in store.requests.indices where store.requests[i].collectionId == id {
            store.requests[i].collectionId = nil
        }
        if store.selectedCollectionID == id {
            store.selectedCollectionID = nil
        }
        store.saveToDisk()
    }
}
