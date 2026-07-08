import SwiftUI
import SwiftData

/// Settings screen for the optional cross-app bridge to Social Climber: a
/// single on/off toggle plus a transparent look at what's shared and what's
/// read. There's no separate sign-in flow here, unlike Google Calendar:
/// "linking" just means both apps sit in the same App Group container, so
/// this screen is status plus a kill switch, backed entirely by
/// CrossAppIntegrationManager / SharedContextStore.
///
/// This screen is also the one place that kicks off App Group container
/// resolution for a fresh install (see AppGroupContainerCache): opening it
/// starts the timed background lookup, the status row stays live while the
/// check runs, and Check Again clears a slow/interrupted-attempt suspension.
struct SocialClimberLinkView: View {
    @Query private var settingsList: [UserSettings]

    private var settings: UserSettings? { settingsList.first }

    /// Cached and refreshed by `refresh()`, not recomputed from the view
    /// body: reading the shared JSON file is real I/O and the body
    /// re-evaluates on things as small as the toggle switching.
    @State private var lookupState: AppGroupLookupState = .notStarted
    @State private var socialClimberContext: SocialClimberPublicContext?
    @State private var socialClimberIsFresh = false

    var body: some View {
        Form {
            if let settings {
                linkSection(settings)
            }
            statusSection
            aboutSection
        }
        .navigationTitle("Social Climber")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { PerfLog.event("nav.socialClimber.appear") }
        .task {
            AppGroupContainerLocator.beginResolvingContainer()
            await pollWhileChecking()
        }
    }

    /// Keeps the status row live while the background lookup runs (cheap
    /// lock reads once a second), then settles on the final state. Bounded
    /// so a pathologically slow lookup can't keep this task alive forever;
    /// cancelled automatically when the screen disappears.
    private func pollWhileChecking() async {
        refresh()
        for _ in 0..<40 {
            guard lookupState == .checking || lookupState == .notStarted else { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            refresh()
        }
        refresh()
    }

    private func refresh() {
        lookupState = AppGroupContainerLocator.lookupState
        let fetched = SharedContextStore.readSocialClimberContext()
        socialClimberContext = fetched
        if let fetched, fetched.schemaVersion >= SocialClimberPublicContext.expectedSchemaVersion {
            let age = Date().timeIntervalSince(fetched.updatedAt)
            socialClimberIsFresh = age >= 0 && age <= CrossAppIntegrationManager.staleAfter
        } else {
            socialClimberIsFresh = false
        }
    }

    private func linkSection(_ settings: UserSettings) -> some View {
        @Bindable var settings = settings
        return Section {
            Toggle("Share context with Social Climber", isOn: $settings.crossAppSharingEnabled)
        } footer: {
            Text("When on, LockedInFit publishes a small daily summary for Social Climber to read, and turns Social Climber's upcoming-event context into its own checklist suggestions. Turn this off to keep LockedInFit fully self-contained.")
        }
    }

    private var statusSection: some View {
        Section {
            HStack {
                Text("App Group")
                Spacer()
                appGroupStatusText
            }
            HStack {
                Text("Social Climber")
                Spacer()
                statusText(socialClimberIsFresh, on: "Linked", off: socialClimberContext == nil ? "Not detected" : "Found, but stale")
            }
            if let context = socialClimberContext {
                LabeledContent("Last updated", value: Formatters.mediumDate(context.updatedAt))
            }
            if lookupState == .unavailable || lookupState == .disabled {
                Button {
                    AppGroupContainerLocator.retryContainerLookup()
                    Task { await pollWhileChecking() }
                } label: {
                    Label("Check Again", systemImage: "arrow.clockwise")
                }
            }
        } header: {
            Text("Status")
        } footer: {
            if lookupState == .unavailable || lookupState == .disabled {
                Text("If this stays unavailable, both apps need the same App Group (\(AppGroupContainerLocator.appGroupIdentifier)) enabled under Signing & Capabilities in Xcode, with valid provisioning for each. The console logs how long the check took (appGroup.lookup.finished).")
            }
        }
    }

    @ViewBuilder
    private var appGroupStatusText: some View {
        switch lookupState {
        case .available:
            Text("Available").font(.caption).foregroundStyle(.green)
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Checking…").font(.caption).foregroundStyle(.secondary)
            }
        case .notStarted:
            Text("Checking…").font(.caption).foregroundStyle(.secondary)
        case .unavailable:
            Text("Not available on this build").font(.caption).foregroundStyle(.secondary)
        case .disabled:
            Text("Suspended after a slow check").font(.caption).foregroundStyle(.orange)
        }
    }

    private func statusText(_ ok: Bool, on: String, off: String) -> some View {
        Text(ok ? on : off)
            .font(.caption)
            .foregroundStyle(ok ? .green : .secondary)
    }

    private var aboutSection: some View {
        Section {
            Text("""
            LockedInFit and Social Climber stay fully separate apps with their own private storage; \
            neither can read the other's database. The only thing shared is a small, versioned JSON \
            file in a shared App Group container. LockedInFit publishes today's sleep score, energy \
            and recovery level, workout and nutrition status, checklist completion, and the titles of \
            due tasks, but never food logs, photos, exact measurements, or notes. It reads Social \
            Climber's upcoming-event context the same way, and only reacts to it when that data is \
            present and less than 24 hours old; stale or missing data is treated as if Social Climber \
            weren't installed at all.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
        } header: {
            Text("How this works")
        }
    }
}
