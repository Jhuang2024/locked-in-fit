import SwiftUI

// MARK: - StarRatingView

/// Interactive 1–5 star rating control. Tapping a star sets the rating;
/// tapping the currently-selected star again clears it back to 0 (unrated),
/// so no separate "clear" affordance is needed anywhere it's used.
struct StarRatingView: View {
    @Binding var rating: Int
    var starSize: CGFloat = 26

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...FoodRatingService.maxRating, id: \.self) { star in
                Button {
                    withAnimation(.snappy) {
                        rating = (rating == star) ? 0 : star
                    }
                } label: {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .font(.system(size: starSize))
                        .foregroundStyle(star <= rating ? Color.yellow : Color.secondary.opacity(0.45))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
            }
            if rating > 0 {
                Text("\(rating)/\(FoodRatingService.maxRating)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }
        }
        .sensoryFeedback(.selection, trigger: rating)
        .accessibilityElement(children: .contain)
        .accessibilityValue(rating > 0 ? "Rated \(rating) of \(FoodRatingService.maxRating)" : "Not rated")
    }
}

// MARK: - StarRatingBadge

/// Compact read-only rating display for list rows and cards: a filled star
/// plus the number. Renders nothing at rating 0 so unrated rows stay clean.
struct StarRatingBadge: View {
    let rating: Int

    var body: some View {
        if rating > 0 {
            HStack(spacing: 2) {
                Image(systemName: "star.fill")
                Text("\(rating)")
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(.yellow)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.yellow.opacity(0.14), in: Capsule())
            .accessibilityLabel("Rated \(rating) of \(FoodRatingService.maxRating) stars")
        }
    }
}
