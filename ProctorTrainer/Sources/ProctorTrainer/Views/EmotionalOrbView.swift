import SwiftUI

struct EmotionalOrbView: View {
    @ObservedObject var viewModel: FridayViewModel
    
    @State private var phase: Double = 0.0
    
    var body: some View {
        ZStack {
            // Background Glow
            Circle()
                .fill(orbColor.opacity(0.3))
                .blur(radius: 50)
                .frame(width: 250, height: 250)
                .scaleEffect(viewModel.currentState == .speaking ? 1.0 + viewModel.micAmplitude * 0.2 : 1.0)
            
            if #available(macOS 15.0, *) {
                meshGradientView
                    .frame(width: 200, height: 200)
                    .mask(Circle())
            } else {
                fallbackOrbView
            }
            
            // Core Logic/Canvas for fine details
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = size.width * 0.4
                
                // Draw some organic "rays" or "particles" based on state
                drawStates(in: context, size: size, center: center, radius: radius)
            }
            .frame(width: 300, height: 300)
        }
        .phaseAnimator([0, 1], trigger: viewModel.currentState) { content, phase in
            content
                .scaleEffect(viewModel.currentState == .processing ? 0.95 + (phase * 0.05) : (viewModel.currentState == .listening ? 1.0 + (phase * 0.08) : 1.0))
                .rotationEffect(.degrees(viewModel.currentState == .processing ? phase * 360 : 0))
                .offset(y: viewModel.currentState == .idle ? phase * 10 : 0)
        } animation: { phase in
            switch viewModel.currentState {
            case .processing:
                return .linear(duration: 2).repeatForever(autoreverses: false)
            case .idle:
                // Gentle floating spring
                return .spring(duration: 2.0, bounce: 0.3).repeatForever(autoreverses: true)
            case .listening:
                // Rapid reactive spring
                return .spring(duration: 0.5, bounce: 0.5).repeatForever(autoreverses: true)
            case .speaking:
                // Punchy vocal spring
                return .snappy(duration: 0.3, extraBounce: 0.2)
            default:
                // Smooth transition spring
                return .spring(duration: 0.8, bounce: 0.4)
            }
        }
    }
    
    @available(macOS 15.0, *)
    var meshGradientView: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.5, 0.5], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1]
            ],
            colors: meshColors
        )
    }
    
    var fallbackOrbView: some View {
        Circle()
            .fill(
                RadialGradient(
                    gradient: Gradient(colors: [orbColor, orbColor.opacity(0.5), .clear]),
                    center: .center,
                    startRadius: 0,
                    endRadius: 100
                )
            )
            .frame(width: 200, height: 200)
    }
    
    private var orbColor: Color {
        switch viewModel.currentState {
        case .idle: return .cyan
        case .listening: return .green
        case .processing: return .purple
        case .speaking: return .white
        case .error: return .red
        case .scanning: return .yellow
        case .recognized: return .emerald
        case .idle where viewModel.emotionalState == "JEALOUS": return .indigo
        }
    }
    
    private var meshColors: [Color] {
        switch viewModel.currentState {
        case .idle: return [.blue, .cyan, .blue, .cyan, .blue.opacity(0.8), .cyan, .blue, .cyan, .blue]
        case .listening: return [.green, .emerald, .green, .emerald, .white, .emerald, .green, .emerald, .green]
        case .processing: return [.purple, .indigo, .pink, .indigo, .purple, .pink, .purple, .indigo, .purple]
        case .speaking: return [.white, .blue, .white, .blue.opacity(0.5), .white, .blue.opacity(0.5), .white, .blue, .white]
        case .error: return [.red, .orange, .red, .orange, .black, .orange, .red, .orange, .red]
        case .scanning: return [.yellow, .orange, .yellow, .white, .yellow, .orange, .yellow, .white, .yellow]
        case .recognized: return [.emerald, .green, .emerald, .white, .emerald, .green, .emerald, .white, .emerald]
        case .idle where viewModel.emotionalState == "JEALOUS": return [.indigo, .blue, .black, .indigo, .purple, .black, .indigo, .blue, .purple]
        }
    }
    
    private func drawStates(in context: GraphicsContext, size: CGSize, center: CGPoint, radius: CGFloat) {
        // Implement state-specific canvas drawings
        let time = Date().timeIntervalSince1970
        
        switch viewModel.currentState {
        case .listening:
            // Ripple waves
            for i in 0..<3 {
                let rippleRadius = radius + CGFloat(sin(time * 5 + Double(i))) * 10 * viewModel.micAmplitude
                var path = Path()
                path.addEllipse(in: CGRect(x: center.x - rippleRadius, y: center.y - rippleRadius, width: rippleRadius * 2, height: rippleRadius * 2))
                context.stroke(path, with: .color(.green.opacity(0.5 - Double(i) * 0.1)), lineWidth: 2)
            }
            
        case .speaking:
            // Vibrating particles
            for _ in 0..<20 {
                let angle = Double.random(in: 0...2 * .pi)
                let distance = radius + CGFloat.random(in: -20...20) * viewModel.micAmplitude
                let point = CGPoint(
                    x: center.x + cos(angle) * distance,
                    y: center.y + sin(angle) * distance
                )
                context.fill(Path(ellipseIn: CGRect(x: point.x, y: point.y, width: 4, height: 4)), with: .color(.blue.opacity(0.7)))
            }
            
        case .scanning:
            // Rotating searchlight effect
            let angle = time * 2.0
            var path = Path()
            path.move(to: center)
            path.addArc(center: center, radius: radius * 1.5, startAngle: .degrees(angle * 180 / .pi), endAngle: .degrees((angle + 0.5) * 180 / .pi), clockwise: false)
            path.closeSubpath()
            context.fill(path, with: .color(.yellow.opacity(0.3)))
            
        case .error:
            // Jagged lines
            var path = Path()
            path.move(to: CGPoint(x: center.x - radius, y: center.y))
            for i in 0..<10 {
                let x = center.x - radius + (radius * 2 * CGFloat(i) / 10)
                let y = center.y + CGFloat.random(in: -30...30)
                path.addLine(to: CGPoint(x: x, y: y))
            }
            context.stroke(path, with: .color(.red), lineWidth: 3)
            
        default:
            break
        }
    }
}

// Helper for Emerald color if not present
extension Color {
    static let emerald = Color(red: 0.31, green: 0.78, blue: 0.47)
}
