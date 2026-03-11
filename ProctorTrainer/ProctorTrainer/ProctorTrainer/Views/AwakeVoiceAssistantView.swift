import SwiftUI
import Combine

struct AwakeVoiceAssistantView: View {
    @ObservedObject var viewModel: FridayViewModel
    
    @State private var phase: Double = 0.0
    @State private var time: Double = 0.0
    
    let timer = Timer.publish(every: 0.016, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            // 1. Bottom Shadow / Glow
            RadialGradient(
                gradient: Gradient(colors: [assistantColor.opacity(0.4), .clear]),
                center: .bottom,
                startRadius: 0,
                endRadius: 400
            )
            .frame(height: 300)
            .offset(y: 150)
            .blur(radius: 60)
            
            // 2. High-Fidelity Fluid Waves
            Canvas { context, size in
                let midY = size.height / 2
                let width = size.width
                
                // Draw multiple overlapping waves for "Realistic" depth
                for i in 0..<3 {
                    let wavePhase = phase + Double(i) * 0.8
                    let waveOpacity = 0.8 - Double(i) * 0.2
                    let waveHeight: CGFloat = (viewModel.currentState == .speaking || viewModel.currentState == .listening) 
                        ? CGFloat(viewModel.micAmplitude * 120) 
                        : 8.0
                    
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: midY))
                    
                    for x in stride(from: 0, to: width, by: 1) {
                        let relativeX = x / width
                        let sine = sin(relativeX * 5.0 + wavePhase)
                        // Taper edges to make it look organic
                        let mask = sin(relativeX * .pi)
                        let y = midY + CGFloat(sine) * waveHeight * CGFloat(mask)
                        
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                    
                    context.stroke(
                        path, 
                        with: .linearGradient(
                            Gradient(colors: [assistantColor.opacity(0), assistantColor.opacity(waveOpacity), assistantColor.opacity(0)]),
                            startPoint: .init(x: 0, y: midY),
                            endPoint: .init(x: width, y: midY)
                        ),
                        lineWidth: 2.0 + Double(i)
                    )
                    
                    // Add "Glow" version of the path
                    context.addFilter(.blur(radius: 5))
                    context.stroke(path, with: .color(assistantColor.opacity(0.35)), lineWidth: 6)
                }
            }
            .frame(height: 200)
            .blendMode(.plusLighter)
            
            // 3. Neural Particles Swarm
            TimelineView(.animation) { tl in
                Canvas { context, size in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    
                    for i in 0..<15 {
                        let angle = Double(i) * (2.0 * .pi / 15) + t * 0.5
                        let distance = 40.0 + sin(t + Double(i)) * 20.0
                        let x = center.x + CGFloat(cos(angle)) * CGFloat(distance)
                        let y = center.y + CGFloat(sin(angle)) * CGFloat(distance)
                        
                        let pSize = 2.0 + sin(t * 2 + Double(i)) * 1.5
                        let dot = Path(ellipseIn: CGRect(x: x, y: y, width: pSize, height: pSize))
                        
                        context.fill(dot, with: .color(assistantColor.opacity(0.6)))
                        context.addFilter(.blur(radius: 1))
                    }
                }
            }
            .frame(height: 200)
        }
        .onReceive(timer) { _ in
            phase += 0.06 // Speed of the fluid wave
        }
    }
    
    private var assistantColor: Color {
        switch viewModel.currentState {
        case .idle: return .blue
        case .listening: return .cyan
        case .processing: return .purple
        case .speaking: return .white
        case .error: return .red
        case .scanning: return .yellow
        case .recognized: return .green
        }
    }
}
