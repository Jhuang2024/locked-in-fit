import SwiftUI
import SwiftData

/// Google Calendar connection flow. Entirely optional; the app never requires
/// it. Uses the system browser (OAuth + PKCE) with the narrow calendar.events
/// scope; tokens live in the Keychain only.
struct GoogleCalendarConnectView: View {
    @Environment(\.modelContext) private var context
    @Query private var connectionStates: [CalendarConnectionState]

    @State private var clientIDInput = ""
    @State private var connecting = false
    @State private var errorMessage: String?
    @State private var confirmDisconnect = false

    private var service: GoogleCalendarService { .shared }
    private var connectionState: CalendarConnectionState? { connectionStates.first }

    var body: some View {
        Form {
            if service.isConnected {
                connectedSection
            } else {
                setupSection
                connectSection
            }

            Section {
                Text("""
                LockedInFit only requests the narrow "calendar.events" scope; it can create, update, \
                and delete events it made, and nothing else. Sign-in happens in the system browser via \
                Google OAuth with PKCE; no password ever touches the app, no client secret is embedded, \
                and tokens are stored in the iOS Keychain, never in the database. Disconnect anytime to \
                revoke access.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("How access works")
            }
        }
        .navigationTitle("Google Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneToolbar()
        .onAppear {
            clientIDInput = service.clientID ?? ""
            ensureConnectionState()
        }
        .confirmationDialog("Disconnect Google Calendar?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) {
                Task { await disconnect() }
            }
        }
    }

    private var connectedSection: some View {
        Section {
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(service.connectedEmail ?? "Connected")
                        .font(.subheadline.weight(.semibold))
                    Text("Scope: calendar events only")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let lastSync = connectionState?.lastSyncDate {
                LabeledContent("Last sync", value: Formatters.mediumDate(lastSync))
            }
            Button("Disconnect", role: .destructive) { confirmDisconnect = true }
        } header: {
            Text("Connection")
        }
    }

    private var setupSection: some View {
        Section {
            TextField("xxxx.apps.googleusercontent.com", text: $clientIDInput)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .font(.caption)
        } header: {
            Text("Google OAuth Client ID")
        } footer: {
            Text("""
            One-time setup: create a free OAuth "iOS" client ID in Google Cloud Console \
            (APIs & Services → Credentials) with this app's bundle ID, enable the Google Calendar API, \
            and paste the client ID here. iOS OAuth clients have no secret; the ID is safe to store.
            """)
        }
    }

    private var connectSection: some View {
        Section {
            Button {
                Task { await connect() }
            } label: {
                if connecting {
                    HStack { ProgressView(); Text("Waiting for Google…") }
                } else {
                    Label("Connect Google Calendar", systemImage: "person.crop.circle.badge.checkmark")
                }
            }
            .disabled(connecting || clientIDInput.trimmingCharacters(in: .whitespaces).isEmpty)
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } footer: {
            Text("Calendar sync is optional. Looks tracking, checklists, and workout schedules all work without it.")
        }
    }

    // MARK: - Actions

    private func connect() async {
        connecting = true
        defer { connecting = false }
        errorMessage = nil
        service.saveClientID(clientIDInput)
        do {
            let email = try await service.connect()
            ensureConnectionState()
            connectionState?.isConnected = true
            connectionState?.email = email
            connectionState?.grantedScopes = [GoogleCalendarService.eventsScope]
            connectionState?.lastSyncDate = nil
        } catch GoogleCalendarError.cancelled {
            // User backed out; not an error state worth showing.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func disconnect() async {
        await service.disconnect()
        connectionState?.isConnected = false
        connectionState?.email = ""
        connectionState?.grantedScopes = []
        connectionState?.lastSyncDate = nil
    }

    private func ensureConnectionState() {
        if connectionStates.isEmpty {
            context.insert(CalendarConnectionState())
        }
    }
}
