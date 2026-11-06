import SwiftUI

/// Horizontal Liquid Glass pill bar to switch dashboard sections.
/// Liquid Glass styling applies to the floating control layer, matching Apple HIG.
struct SectionPillBar: View {
    @Binding var selection: DashboardSection
    @Namespace private var animation

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DashboardSection.allCases) { section in
                        let isSelected = selection == section
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                selection = section
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: section.systemImage)
                                    .imageScale(.small)
                                Text(section.title)
                                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .foregroundColor(isSelected ? .primary : .secondary)
                            .background {
                                if isSelected {
                                    Capsule()
                                        .fill(.regularMaterial)
                                        .glassEffect(.regular, in: .capsule)
                                        .matchedGeometryEffect(id: "selectedPill", in: animation)
                                        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                                } else {
                                    Capsule()
                                        .fill(.quaternary.opacity(0.5))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                        .id(section)
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    }
                }
                .padding(.horizontal, 16)
            }
            .onChange(of: selection) { _, newSection in
                withAnimation {
                    proxy.scrollTo(newSection, anchor: .center)
                }
            }
        }
    }
}
