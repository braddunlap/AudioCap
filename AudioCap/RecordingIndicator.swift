import SwiftUI

struct RecordingIconTransitionModifier: ViewModifier {
    var isIdentity: Bool

    func body(content: Content) -> some View {
        content
            .saturation(!isIdentity ? 1.5 : 1)
            .rotationEffect(.degrees(!isIdentity ? 200 : 0))
            .blur(radius: !isIdentity ? 6 : 0)
            .scaleEffect(!isIdentity ? 0.5 : 1)
    }
}

struct RecordingIndicator: View {
    let appIcon: NSImage
    let isRecording: Bool
    let audioLevel: Float
    var size: CGFloat = 22

    private var isHot: Bool {
        audioLevel > 0.03 // You may want to tune this value!
    }

    @Environment(\.colorScheme)
    private var colorScheme

    var body: some View {
        ZStack {
            if !isRecording {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .transition(
                        .asymmetric(
                            insertion: .modifier(active: RecordingIconTransitionModifier(isIdentity: false), identity: RecordingIconTransitionModifier(isIdentity: true)).animation(.bouncy(extraBounce: 0.3).delay(0.2)),
                            removal: .modifier(active: RecordingIconTransitionModifier(isIdentity: false), identity: RecordingIconTransitionModifier(isIdentity: true)).animation(.bouncy(extraBounce: 0.3))
                        )
                    )
            }

            if isRecording {
                // Animate between white/red depending on audioLevel
                recordingView
                    .transition(
                        .asymmetric(
                            insertion: .scale.combined(with: .opacity).animation(.bouncy(extraBounce: 0.3).delay(0.2)),
                            removal: .scale.combined(with: .opacity).animation(.bouncy)
                        )
                    )
            }
        }
        .animation(.spring(response: 0.1, dampingFraction: 0.7), value: audioLevel)
    }

    @ViewBuilder
    private var recordingView: some View {
        ZStack {
            iconView
                .blur(radius: 16, opaque: true)
                .clipShape(Circle())
                .brightness(colorScheme == .dark ? -0.3 : 0.3)
                .compositingGroup()
                .opacity(0.6)
                .shadow(color: .black.opacity(0.2), radius: 2)

            if isHot {
                Circle()
                    .fill(Color.red)
                    .frame(width: size, height: size)
                    .opacity(0.60)
                    .blendMode(.plusLighter)
                    .animation(.easeInOut(duration: 0.08), value: isHot)
            }

            ZStack {
                iconView
                    .frame(width: size * 0.5, height: size * 0.5)
                    .blur(radius: 10, opaque: true)
                    .brightness(colorScheme == .dark ? 0.4 : -0.2)
                    .saturation(colorScheme == .dark ? 1 : 1.3)
                    .clipShape(Circle())
                    .blendMode(.plusDarker)

                Circle()
                    .fill(colorScheme == .dark ? .white : .black)
                    .frame(width: size * 0.5 * (1.0 + CGFloat(audioLevel * 1.5)),
                           height: size * 0.5 * (1.0 + CGFloat(audioLevel * 1.5)))
                    .opacity(colorScheme == .dark ? 0.5 : 0.3)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white, lineWidth: 0.5)
                            .opacity(0.1)
                    }
                    .blendMode(colorScheme == .dark ? .plusLighter : .plusDarker)
            }
            .phaseAnimator([0, 1]) { content, phase in
                content
                    .scaleEffect(phase == 1 ? 1.5 : 1)
                    .opacity(phase == 1 ? 1 : 0.7)
            } animation: { _ in Animation.bouncy(duration: 2.4).delay(0.6) }
        }
        .padding(4)
        .background {
            iconView
                .clipShape(Circle())
                .blur(radius: 5)
                .saturation(2)
                .brightness(colorScheme == .dark ? -0.3 : -0.1)
                .opacity(0.5)
        }
        .padding(-4)
    }

    @ViewBuilder
    private var iconView: some View {
        Image(nsImage: appIcon)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
    }
}

#if DEBUG
struct RecordingIndicatorPreview: View {
    @State private var isRecording = false
    @State private var previewAudioLevel: Float = 0.0

    let icon = NSWorkspace.shared.icon(forFile: "/System/Applications/Music.app")

    var body: some View {
        VStack {
            HStack(spacing: 8) {
                RecordingIndicator(
                    appIcon: icon,
                    isRecording: isRecording,
                    audioLevel: previewAudioLevel
                )

                Text(isRecording ? "Recording from Music (Level: \(String(format: "%.2f", previewAudioLevel)))" : "Ready to Record from Music")
                    .font(.headline)
                    .contentTransition(.identity)
            }
            .animation(.bouncy(extraBounce: 0.1), value: isRecording)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(32)
            .contentShape(Rectangle())
            .onTapGesture {
                isRecording.toggle()
                if !isRecording {
                    previewAudioLevel = 0.0
                }
            }
            
            if isRecording {
                Slider(value: $previewAudioLevel, in: 0...1)
                    .padding()
            }
        }
    }
}
#Preview("Recording Indicator") {
    RecordingIndicatorPreview()
}
#endif
