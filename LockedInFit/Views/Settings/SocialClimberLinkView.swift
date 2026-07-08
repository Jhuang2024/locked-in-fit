import SwiftUI
import SwiftData

/// Settings screen for the optional cross-app bridge to Social Climber: a
/// single on/off toggle plus a transparent look at what's shared and what's
/// read. There's no separate sign-in flow here — unlike Google Calendar,
/// "linking" just means both apps sit in the same App Group container, so
/// this screen is status plus a kill switch, backed entirely by
/// CrossAppIntegrationManager / SharedContextStore.
struct SocialClimberLinkView: View {
    @Query private var settingsList: [UserSettings]

    private var settings: UserSettings? { settingsList.first }
    private var appGroupAvailable: Bool { AppGroupContainerLocator().containerURL != nil }
    private var socialClimberContext: SocialClimberPublicContext? { SharedContextStore.readSocialClimberContext() }
    private var socialClimberIsFresh: Bool { CrossAppIntegrationManager.readSocialContext() != nil }

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
        Section("Status") {
            HStack {
                Text("App Group")
                Spacer()
                statusText(appGroupAvailable, on: "Available", off: "Not available on this build")
            }
            HStack {
                Text("Social Climber")
                Spacer()
                statusText(socialClimberIsFresh, on: "Linked", off: socialClimberContext == nil ? "Not detected" : "Found, but stale")
            }
            if let context = socialClimberContext {
                LabeledContent("Last updated", value: Formatters.mediumDate(context.updatedAt))
            }
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
            due tasks — never food logs, photos, exact measurements, or notes. It reads Social \
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
