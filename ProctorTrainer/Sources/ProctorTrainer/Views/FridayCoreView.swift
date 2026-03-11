import SwiftUI

struct FridayCoreView: View {
    @StateObject private var viewModel = FridayViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Status Bar (Pro Look)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FRIDAY v2.5 PRO")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(.blue)
                    Text("Uptime: 99.9% • Watchdog Active")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                HStack(spacing: 12) {
                    StatusIndicator(label: "AI", isActive: true, color: .blue)
                    StatusIndicator(label: "VOICE", isActive: viewModel.currentState == .listening, color: .green)
                    StatusIndicator(label: "VISION", isActive: true, color: .purple)
                }
            }
            .padding(.horizontal, 25)
            .padding(.top, 20)
            
            Spacer()
            
            EmotionalOrbView(viewModel: viewModel)
                .frame(width: 350, height: 350)
                .shadow(color: .blue.opacity(0.2), radius: 30)
            
            Text(viewModel.statusMessage)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, 10)
            
            // New: Interaction History (Glassmorphism)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .frame(maxHeight: 200)
                .background(.ultraThinMaterial)
                .cornerRadius(25)
                .padding(.horizontal, 30)
                .padding(.top, 25)
                .onChange(of: viewModel.messages) { _ in
                    if let lastId = viewModel.messages.last?.id {
                        withAnimation { proxy.scrollTo(lastId) }
                    }
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Color.black.ignoresSafeArea()
        )
        .onAppear {
            viewModel.startSimulatingMic()
        }
    }
}

struct StatusIndicator: View {
    let label: String
    let isActive: Bool
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isActive ? color : Color.gray)
                .frame(width: 6, height: 6)
                .shadow(color: color, radius: isActive ? 4 : 0)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white.opacity(0.7))
        }
    }
}

struct ChatBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if !message.isUser { Spacer() }
            
            Text(message.text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    message.isUser ? 
                    AnyShapeStyle(Color.white.opacity(0.1)) : 
                    AnyShapeStyle(LinearGradient(colors: [.blue.opacity(0.3), .purple.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .cornerRadius(18)
                .foregroundColor(.white)
            
            if message.isUser { Spacer() }
        }
    }
}

#Preview {
    FridayCoreView()
        .background(Color.black)
}
