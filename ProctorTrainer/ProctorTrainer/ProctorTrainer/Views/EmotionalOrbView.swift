import SwiftUI
import Combine

struct EmotionalOrbView: View {
    @ObservedObject var viewModel: FridayViewModel
    
    @State private var phase: Double = 0.0
    @State private var innerRotation: Double = 0.0
    @State private var scanLineOffset: CGFloat = -150
    @State private var driftRotation: Angle = .zero
    
    // Particle data
    struct Particle: Identifiable {
        let id = UUID()
        var position: CGPoint
        var speed: CGFloat
        var angle: Double
    }
    @State private var particles: [Particle] = (0..<40).map { _ in 
        Particle(position: .zero, speed: CGFloat.random(in: 1...3), angle: Double.random(in: 0...2 * .pi))
    }
    
    // Timer for constant animation even when idle
    let timer = Timer.publish(every: 0.02, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            // 0. The 3D Depth Drift Container
            Group {
                // 1. Deep Background Glow
                Circle()
                    .fill(orbColor.opacity(0.15))
                    .blur(radius: 60)
                    .frame(width: 320, height: 320)
                    .scaleEffect(viewModel.currentState == .speaking ? 1.0 + viewModel.micAmplitude * 0.4 : 1.0)
                
                // 2. The Glass Outer Shell
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.35), .clear, .white.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.0
                    )
                    .frame(width: 215, height: 215)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .opacity(0.25)
                    )

                // 3. The Core Liquid Orb
                if #available(macOS 15.0, *) {
                    meshGradientView
                        .frame(width: 200, height: 200)
                        .mask(Circle())
                        .shadow(color: orbColor.opacity(0.6), radius: 25)
                } else {
                    fallbackOrbView
                }
                
                // 4. Energy Particles / Sinelines
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let radius = size.width * 0.42
                    
                    drawPlasmaField(in: context, size: size, center: center, radius: radius)
                }
                .frame(width: 300, height: 300)
                .blendMode(.plusLighter)
                
                // 5. Quantum Small Particles
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        let center = CGPoint(x: size.width / 2, y: size.height / 2)
                        for particle in particles {
                            let time = timeline.date.timeIntervalSinceReferenceDate
                            let x = center.x + cos(particle.angle + time * Double(particle.speed)) * (100 + sin(time) * 10)
                            let y = center.y + sin(particle.angle + time * Double(particle.speed)) * (100 + cos(time) * 10)
                            
                            var p = Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2))
                            context.fill(p, with: .color(orbColor.opacity(0.7)))
                            context.addFilter(.blur(radius: 1))
                        }
                    }
                }
                .frame(width: 300, height: 300)
            }
            .rotation3DEffect(driftRotation, axis: (x: 1, y: 1, z: 0))
            
            // 6. Holographic Scan Sweep
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, orbColor.opacity(0.5), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 250, height: 2)
                .offset(y: scanLineOffset)
                .mask(Circle().frame(width: 210, height: 210))
        }
        .onReceive(timer) { _ in
            withAnimation(.linear(duration: 0.02)) {
                phase += 0.05
                innerRotation += 0.5
                scanLineOffset += 2
                if scanLineOffset > 150 { scanLineOffset = -150 }
                
                // Slow drift rotation
                let t = Date().timeIntervalSinceReferenceDate
                driftRotation = .degrees(3.0 * sin(t * 0.5))
            }
        }
        .phaseAnimator([0, 1], trigger: viewModel.currentState) { content, phase in
            content
                .scaleEffect(viewModel.currentState == .processing ? 0.98 + (phase * 0.04) : 1.0)
        } animation: { _ in
            .easeInOut(duration: 1.5).repeatForever(autoreverses: true)
        }
    }
    
    @available(macOS 15.0, *)
    var meshGradientView: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0, 0], [0.5, Float(0.2 * sin(phase))], [1, 0],
                [Float(0.2 * cos(phase)), 0.5], [0.5, 0.5], [Float(1.0 - 0.2 * cos(phase)), 0.5],
                [0, 1], [0.5, Float(1.0 - 0.2 * sin(phase))], [1, 1]
            ],
            colors: meshColors
        )
        .blur(radius: 10)
        .rotationEffect(.degrees(innerRotation * 0.2))
    }
    
    var fallbackOrbView: some View {
        Circle()
            .fill(
                RadialGradient(
                    gradient: Gradient(colors: [orbColor, orbColor.opacity(0.6), .clear]),
                    center: .center,
                    startRadius: 0,
                    endRadius: 100
                )
            )
            .frame(width: 200, height: 200)
            .blur(radius: 5)
    }
    
    private var orbColor: Color {
        switch viewModel.currentState {
        case .idle: return .cyan
        case .listening: return .green
        case .processing: return .indigo
        case .speaking: return .white
        case .error: return .red
        case .scanning: return .yellow
        case .recognized: return .emerald
        }
    }
    
    private var meshColors: [Color] {
        let base = orbColor
        switch viewModel.currentState {
        case .idle: 
            return [.blue, .cyan, .blue, .cyan, .white.opacity(0.8), .cyan, .blue, .cyan, .blue]
        case .listening: 
            return [.green, .emerald, .green, .emerald, .white, .emerald, .green, .emerald, .green]
        case .processing: 
            return [.purple, .indigo, .purple, .pink, .white, .pink, .indigo, .purple, .indigo]
        case .speaking: 
            return [.white, .blue.opacity(0.6), .white, .cyan.opacity(0.4), .white, .cyan.opacity(0.4), .white, .blue, .white]
        case .scanning:
            return [.yellow, .orange, .yellow, .white, .yellow, .orange, .yellow, .white, .yellow]
        default: 
            return [base, base, base, base, .white, base, base, base, base]
        }
    }
    
    private func drawPlasmaField(in context: GraphicsContext, size: CGSize, center: CGPoint, radius: CGFloat) {
        let count = 60
        let baseAlpha = viewModel.currentState == .idle ? 0.2 : 0.6
        
        for i in 0..<count {
            let angle = (Double(i) / Double(count)) * 2.0 * .pi
            let noise = sin(angle * 3 + phase) * 5
            let responsiveRadius = radius + noise + (viewModel.currentState == .speaking ? CGFloat(viewModel.micAmplitude * 50 * sin(angle * 10)) : 0)
            
            let start = CGPoint(
                x: center.x + CGFloat(cos(angle)) * (responsiveRadius - 2),
                y: center.y + CGFloat(sin(angle)) * (responsiveRadius - 2)
            )
            let end = CGPoint(
                x: center.x + CGFloat(cos(angle)) * (responsiveRadius + 2),
                y: center.y + CGFloat(sin(angle)) * (responsiveRadius + 2)
            )
            
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            
            context.stroke(path, with: .color(orbColor.opacity(baseAlpha)), lineWidth: 1.5)
        }
    }
}


// Helper for Emerald color if not present
extension Color {
    static let emerald = Color(red: 0.31, green: 0.78, blue: 0.47)
}
