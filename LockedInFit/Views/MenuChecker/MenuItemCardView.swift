import SwiftUI
import SwiftData

/// One menu-item card. Keeps the surface uncluttered — item name, a couple of
/// bold numbers, and the two distinct score chips — with all the reasoning
/// revealed on tap (the detail screen). The Add button carts the item with its
/// default configuration; tap the card to modify first.
struct MenuItemCardView: View {
    @Environment(\.modelContext) private var context
    let item: MenuItem
    let restaurantName: String
    let profile: ScoringProfile
    var onAdded: (() -> Void)? = nil

    @State private var justAdded = false

    private var resolved: ResolvedMenuItem {
        MenuItemResolver.resolve(item: item, profile: profile)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MenuItemPhoto(assetName: item.photoAssetName, height: 74)
                .frame(width: 74)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(item.name).font(.subheadline.weight(.bold))
                    Spacer()
                    if let price = MenuFormat.price(item.price, code: item.currencyCode) {
                        Text(price).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                if !item.itemDescription.isEmpty {
                    Text(item.itemDescription).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(Int(resolved.perUnit.calories))")
                            .font(.system(.title3, design: .rounded, weight: .heavy))
                        Text("kcal").font(.caption2).foregroundStyle(.secondary)
                    }
                    Text("\(Int(resolved.perUnit.protein))P")
                        .font(.system(.subheadline, design: .rounded, weight: .bold)).foregroundStyle(.red)
                    Spacer()
                }
                HStack(spacing: 6) {
                    HealthChip(score: resolved.healthScore)
                    SatietyChip(score: resolved.satietyScore)
                    NutritionSourceBadge(kind: resolved.sourceKind, compact: true)
                    Spacer()
                    Button {
                        CartManager.add(resolved, restaurantName: restaurantName, context: context)
                        withAnimation(.snappy) { justAdded = true }
                        onAdded?()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { justAdded = false }
                    } label: {
                        Image(systemName: justAdded ? "checkmark.circle.fill" : "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(justAdded ? .green : Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .cardBackground()
    }
}
