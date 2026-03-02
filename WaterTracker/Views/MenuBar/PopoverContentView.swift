import SwiftUI

struct PopoverContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "drop.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Water Tracker")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Your hydration companion")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 280)
    }
}

#Preview {
    PopoverContentView()
}
