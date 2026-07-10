import SwiftUI
import UIKit

// MARK: - MealRowView

struct MealRowView: View {
    let meal: MealLog

    var body: some View {
        HStack(spacing: 12) {
            if let image = ImageStore.load(meal.photoPath) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Image(systemName: meal.mealType.systemImage)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 48, height: 48)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(meal.mealType.label)
                        .font(.subheadline.weight(.semibold))
                    if meal.confidence < 0.8 {
                        Text("±")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    }
                }
                Text(meal.items.isEmpty ? (meal.notes.isEmpty ? "Manual entry" : meal.notes) : meal.items.map(\.name).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if meal.hiddenOilHigh > 0 {
                    Text("Oil +\(Int(meal.hiddenOilLow))–\(Int(meal.hiddenOilHigh)) kcal possible")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(meal.calories))")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                Text("kcal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - HealthScanRowView

struct HealthScanRowView: View {
    let scan: HealthScan

    var body: some View {
        HStack(spacing: 12) {
            if let image = ImageStore.load(scan.photoPath) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Image(systemName: scan.processedLevel.systemImage)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 48, height: 48)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(scan.productName.isEmpty ? "Unnamed product" : scan.productName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(scan.processedLevel.label) · \(Int(scan.calories)) kcal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(scan.healthScore.rounded()))")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(HealthScanCoreSections.scoreColor(scan.healthScore))
                Text("health")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - FoodPresetRowView

struct FoodPresetRowView: View {
    let preset: FoodPreset

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name)
                    .font(.subheadline.weight(.medium))
                Text("\(preset.serving) · P\(Int(preset.protein)) C\(Int(preset.carbs)) F\(Int(preset.fat))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if preset.cookingMethod == .stirFried || preset.cookingMethod == .deepFried || preset.cookingMethod == .braised {
                    Text(HiddenOilEstimator.riskLabel(for: preset.cookingMethod))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Text("\(Int(preset.calories)) kcal")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
        }
    }
}

// MARK: - WorkoutRowView

struct WorkoutRowView: View {
    let workout: Workout

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: workout.completed ? "checkmark.circle.fill" : "circle.dashed")
                .font(.title3)
                .foregroundStyle(workout.completed ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.title)
                    .font(.subheadline.weight(.semibold))
                Text("\(workout.type.label) · \(workout.exerciseList.count) exercises · \(Int(workout.duration)) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Formatters.shortDate(workout.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if workout.totalVolume > 0 {
                    Text("\(Int(workout.totalVolume / 1000))k kg vol")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - ExerciseSetRowView

struct ExerciseSetRowView: View {
    @Bindable var set: WorkoutSet
    let isDurationBased: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text("\(set.order + 1)")
                .font(.caption.bold())
                .frame(width: 22, height: 22)
                .background(Color(.tertiarySystemFill), in: Circle())

            if isDurationBased {
                TextField("sec", value: $set.duration, format: .number)
                    .keyboardType(.numberPad)
                    .frame(width: 60)
                    .textFieldStyle(.roundedBorder)
                Text("sec").font(.caption).foregroundStyle(.secondary)
            } else {
                TextField("kg", value: $set.weight, format: .number)
                    .keyboardType(.decimalPad)
                    .frame(width: 64)
                    .textFieldStyle(.roundedBorder)
                Text("kg ×").font(.caption).foregroundStyle(.secondary)
                TextField("reps", value: $set.reps, format: .number)
                    .keyboardType(.numberPad)
                    .frame(width: 48)
                    .textFieldStyle(.roundedBorder)
            }

            Spacer()

            Button {
                set.completed.toggle()
            } label: {
                Image(systemName: set.completed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(set.completed ? .green : .secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - ProgressPhotoCard

struct ProgressPhotoCard: View {
    let photo: ProgressPhoto

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Formatters.mediumDate(photo.date))
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                thumb(photo.frontPhotoPath, label: "Front")
                thumb(photo.sidePhotoPath, label: "Side")
                thumb(photo.backPhotoPath, label: "Back")
            }
            if !photo.notes.isEmpty {
                Text(photo.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .cardBackground()
    }

    @ViewBuilder
    private func thumb(_ path: String?, label: String) -> some View {
        VStack(spacing: 4) {
            if let image = ImageStore.load(path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 90, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 90, height: 120)
                    .overlay(Image(systemName: "person.fill").foregroundStyle(.quaternary))
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
