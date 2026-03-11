import SwiftUI
import Charts

enum UIType: String, Codable {
    case chart, list, image, security, research
}

struct DynamicUIContent: Identifiable, Equatable {
    let id = UUID()
    let type: UIType
    let title: String
    let data: [String: Any]
    
    static func == (lhs: DynamicUIContent, rhs: DynamicUIContent) -> Bool {
        lhs.id == rhs.id
    }
}

struct StatData: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
}

struct DynamicChartView: View {
    let title: String
    let stats: [StatData]
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.headline)
                .padding(.bottom, 5)
            
            Chart(stats) { item in
                BarMark(
                    x: .value("Label", item.label),
                    y: .value("Value", item.value)
                )
                .foregroundStyle(by: .value("Label", item.label))
            }
            .frame(height: 150)
            .chartLegend(.hidden)
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(15)
        .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
    }
}

struct DynamicListView: View {
    let title: String
    let items: [String]
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.headline)
                .padding(.bottom, 5)
            
            ForEach(items, id: \.self) { item in
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(item)
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(15)
    }
}

struct ResearchCardView: View {
    let title: String
    let summary: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "book.closed.fill")
                    .foregroundColor(.blue)
                Text(title)
                    .font(.headline)
            }
            
            Text(summary)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(5)
            
            HStack {
                Spacer()
                Text("Knowledge Base")
                    .font(.caption2)
                    .foregroundColor(.blue.opacity(0.7))
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(15)
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
    }
}

struct DynamicUIRenderer: View {
    let content: DynamicUIContent
    
    var body: some View {
        Group {
            switch content.type {
            case .chart:
                if let values = content.data["values"] as? [Double],
                   let labels = content.data["labels"] as? [String] {
                    let stats = zip(labels, values).map { StatData(label: $0.0, value: $0.1) }
                    DynamicChartView(title: content.title, stats: stats)
                }
            case .list:
                if let items = content.data["items"] as? [String] {
                    DynamicListView(title: content.title, items: items)
                }
            case .research:
                if let summary = content.data["summary"] as? String {
                    ResearchCardView(title: content.title, summary: summary)
                }
            default:
                EmptyView()
            }
        }
    }
}
