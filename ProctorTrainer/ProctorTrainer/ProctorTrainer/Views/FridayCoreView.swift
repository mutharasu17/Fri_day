import SwiftUI

struct FridayCoreView: View {
    @StateObject private var viewModel = FridayViewModel()
    @ObservedObject private var sharedState = SharedState.shared
    
    var body: some View {
        VStack {
            Spacer()
            
            AwakeVoiceAssistantView(viewModel: viewModel)
                .frame(height: 220)
            
            Text(viewModel.statusMessage)
                .font(.system(size: 24, weight: .light, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .tracking(1.5)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, -20)
            
            Text(viewModel.proctorStatus)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(viewModel.proctorStatus.contains("VIOLATION") ? .red : .cyan.opacity(0.8))
                .padding(.top, 5)
            
            // Generative UI Section
            if let activeUI = sharedState.activeUI {
                DynamicUIRenderer(content: activeUI)
                    .padding()
                    .frame(maxWidth: 400)
            }
            
            // New: Task/Transcript Screen
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 15) {
                        ForEach(viewModel.messages) { message in
                            HStack {
                                if !message.isUser { Spacer() }
                                
                                Text(message.text)
                                    .font(.system(size: 14, weight: .regular, design: .rounded))
                                    .padding()
                                    .background(message.isUser ? Color.white.opacity(0.1) : Color.blue.opacity(0.2))
                                    .cornerRadius(15)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 15)
                                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                    )
                                    .id(message.id)
                                
                                if message.isUser { Spacer() }
                            }
                        }
                    }
                    .padding()
                }
                .frame(maxHeight: 250)
                .background(Color.black.opacity(0.2))
                .cornerRadius(20)
                .padding(.horizontal)
                .padding(.top, 20)
                .onChange(of: viewModel.messages) { _ in
                    if let lastId = viewModel.messages.last?.id {
                        withAnimation { proxy.scrollTo(lastId) }
                    }
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .onAppear {
            viewModel.startSimulatingMic()
        }
    }
}

#Preview {
    FridayCoreView()
        .background(Color.black)
}
