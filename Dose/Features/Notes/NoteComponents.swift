import SwiftUI
import UIKit

/// Multi-select tag chips for the note editor. Bound to a `Set<NoteTag>`; the editor maps that to the
/// note's raw `[String]` tags. Wraps via an adaptive grid so it reflows on any width / text size.
struct TagPicker: View {
    @Binding var selected: Set<NoteTag>

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: DoseSpacing.sm)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: DoseSpacing.sm) {
            ForEach(NoteTag.allCases) { tag in
                let on = selected.contains(tag)
                Button {
                    if on { selected.remove(tag) } else { selected.insert(tag) }
                } label: {
                    Text(tag.rawValue)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, DoseSpacing.sm)
                        .padding(.vertical, 6)
                        .background(on ? AnyShapeStyle(DoseColors.accent) : AnyShapeStyle(DoseColors.neutral.opacity(0.14)),
                                    in: Capsule())
                        .foregroundStyle(on ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(tag.rawValue) tag")
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .padding(.vertical, 2)
    }
}

/// Read-only chips summarizing a note's tags (list rows).
struct NoteTagChips: View {
    let tags: [NoteTag]

    var body: some View {
        HStack(spacing: DoseSpacing.xs) {
            ForEach(tags) { tag in
                Text(tag.rawValue)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(DoseColors.accent.opacity(0.14), in: Capsule())
                    .foregroundStyle(DoseColors.accent)
            }
        }
    }
}

/// A horizontal strip of a note's attached photos, each deletable. Empty state is a caption.
struct PhotoAttachmentRow: View {
    let photos: [NotePhoto]
    var onDelete: (NotePhoto) -> Void

    var body: some View {
        if photos.isEmpty {
            Text("No photos attached").font(.caption).foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DoseSpacing.sm) {
                    ForEach(photos) { photo in
                        if let image = UIImage(data: photo.imageData) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: DoseRadius.small, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    Button { onDelete(photo) } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.subheadline)
                                            .foregroundStyle(.white, .black.opacity(0.55))
                                            .padding(2)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Remove photo")
                                }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}
