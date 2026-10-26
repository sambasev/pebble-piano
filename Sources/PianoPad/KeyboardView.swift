#if os(macOS)
import PianoGraderCore
import SwiftUI

/// A piano keyboard drawn for a pitch range. Keys show their state in fill and shape, never
/// hue alone: a wrong key is pale red with a red rim, a held key is iris, the reference
/// audition is lilac, and the next key to play gets an iris bar along its bottom edge.
struct KeyboardView: View {
    let range: ClosedRange<Int>
    let held: Set<Int>
    let wrong: Set<Int>
    let expected: Set<Int>
    /// Keys sounding in the reference audition.
    var audition: Set<Int> = []
    let showGuide: Bool
    let keyLabel: (Int) -> String?
    /// Keys to find (a lesson's "find it" step): they pulse with an iris ring until played.
    var highlight: Set<Int> = []
    /// The mouse went down on, or was dragged onto, a key. Nil: the keys don't respond to clicks.
    var onPress: ((Int) -> Void)? = nil
    /// The mouse was released, or dragged off the keys.
    var onRelease: (() -> Void)? = nil

    /// Black keys: this share of a white key's width, centred on the boundary, and this share
    /// of the height. Shared by the drawing and the mouse hit test so they always agree.
    private static let blackWidth: CGFloat = 0.62
    private static let blackHeight: CGFloat = 0.58

    private static let blackPitchClasses: Set<Int> = [1, 3, 6, 8, 10]

    private func isBlack(_ pitch: Int) -> Bool { Self.blackPitchClasses.contains(pitch % 12) }

    /// Space at each end for the out-of-range arrows (kept even when empty, so the keys don't move).
    private static let edgeWidth: CGFloat = 18

    var body: some View {
        HStack(spacing: 4) {
            edgeMarker(below: true)
            keys
            edgeMarker(below: false)
        }
    }

    /// Notes sounding below (or above) the keys: faint "‹‹" (or "››"), a little stronger when
    /// it's a wrong or wanted note.
    private func edgeMarker(below: Bool) -> some View {
        let outside: (Set<Int>) -> Bool = { set in set.contains { below ? $0 < range.lowerBound : $0 > range.upperBound } }
        let any = outside(held) || outside(audition) || outside(wrong) || outside(expected)
        let strong = outside(wrong) || outside(expected)
        return Text(below ? "‹‹" : "››")
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(PP.inkMuted)
            .opacity(any ? (strong ? 0.75 : 0.4) : 0)
            .frame(width: Self.edgeWidth)
            .help(below ? "A note below the keys shown" : "A note above the keys shown")
            .accessibilityHidden(!any)
    }

    private var keys: some View {
        GeometryReader { geo in
            let whites = range.filter { !isBlack($0) }
            let blacks = range.filter { isBlack($0) && whites.contains($0 - 1) }
            let whiteWidth = geo.size.width / CGFloat(max(1, whites.count))
            let height = geo.size.height

            ZStack(alignment: .topLeading) {
                ForEach(Array(whites.enumerated()), id: \.element) { index, pitch in
                    whiteKey(pitch)
                        .frame(width: whiteWidth - 3, height: height)
                        .offset(x: CGFloat(index) * whiteWidth + 1.5)
                }
                ForEach(blacks, id: \.self) { pitch in
                    let index = whites.firstIndex(of: pitch - 1) ?? 0
                    blackKey(pitch)
                        .frame(width: whiteWidth * Self.blackWidth, height: height * Self.blackHeight)
                        .offset(x: CGFloat(index + 1) * whiteWidth - whiteWidth * Self.blackWidth / 2)
                }
                if !highlight.isEmpty {
                    // A slow pulse on the keys to find, drawn above the keys so black keys show too.
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                        let t = context.date.timeIntervalSinceReferenceDate
                        let pulse = 0.5 + 0.5 * sin(t * 2 * .pi / 1.4)
                        ZStack(alignment: .topLeading) {
                            ForEach(Array(whites.enumerated()).filter { highlight.contains($0.element) }, id: \.element) { index, _ in
                                findRing(radius: PP.Radius.key, pulse: pulse)
                                    .frame(width: whiteWidth - 3, height: height)
                                    .offset(x: CGFloat(index) * whiteWidth + 1.5)
                            }
                            ForEach(blacks.filter { highlight.contains($0) }, id: \.self) { pitch in
                                let index = whites.firstIndex(of: pitch - 1) ?? 0
                                findRing(radius: 9, pulse: pulse)
                                    .frame(width: whiteWidth * Self.blackWidth, height: height * Self.blackHeight)
                                    .offset(x: CGFloat(index + 1) * whiteWidth - whiteWidth * Self.blackWidth / 2)
                            }
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { drag in
                        guard let onPress else { return }
                        if let pitch = Self.pitch(at: drag.location, in: geo.size, range: range) {
                            onPress(pitch)
                        } else {
                            onRelease?()
                        }
                    }
                    .onEnded { _ in onRelease?() },
                including: onPress == nil ? .subviews : .all
            )
        }
        .accessibilityHidden(true)
    }

    /// The key under `point` (in the keyboard's own coordinates), black keys first since they
    /// sit on top; nil outside the keys.
    static func pitch(at point: CGPoint, in size: CGSize, range: ClosedRange<Int>) -> Int? {
        let whites = range.filter { !blackPitchClasses.contains($0 % 12) }
        guard !whites.isEmpty, size.width > 0, size.height > 0,
              point.x >= 0, point.x < size.width, point.y >= 0, point.y <= size.height else { return nil }
        let whiteWidth = size.width / CGFloat(whites.count)
        if point.y <= size.height * blackHeight {
            for pitch in range where blackPitchClasses.contains(pitch % 12) {
                guard let index = whites.firstIndex(of: pitch - 1) else { continue }
                let left = CGFloat(index + 1) * whiteWidth - whiteWidth * blackWidth / 2
                if point.x >= left && point.x < left + whiteWidth * blackWidth { return pitch }
            }
        }
        return whites[min(whites.count - 1, Int(point.x / whiteWidth))]
    }

    private func findRing(radius: CGFloat, pulse: Double) -> some View {
        let shape = PPKeyShape(radius: radius)
        return shape.fill(PP.accent.opacity(0.12 + 0.28 * pulse))
            .overlay(shape.stroke(PP.accent.opacity(0.55 + 0.45 * pulse), lineWidth: 3))
    }

    private func isNext(_ pitch: Int) -> Bool {
        showGuide && expected.contains(pitch) && !held.contains(pitch) && !wrong.contains(pitch)
    }

    private func fill(_ pitch: Int, black: Bool) -> Color {
        if wrong.contains(pitch) { return PP.mistakeSoft }
        if held.contains(pitch) { return PP.accent }
        if audition.contains(pitch) { return PP.lilac }
        return black ? PP.keyBlack : PP.keyWhite
    }

    /// Label colour on a key's current fill.
    private func ink(_ pitch: Int, black: Bool) -> Color {
        if wrong.contains(pitch) || audition.contains(pitch) { return PP.ink }
        if held.contains(pitch) { return PP.onAccent }
        return black ? .white : PP.keyLabel
    }

    private func whiteKey(_ pitch: Int) -> some View {
        let shape = PPKeyShape(radius: PP.Radius.key)
        return shape
            .fill(fill(pitch, black: false))
            .overlay(isNext(pitch) ? shape.fill(PP.accent.opacity(0.10)) : nil)
            .overlay(alignment: .bottom) {
                if isNext(pitch) {
                    Rectangle().fill(PP.accent).frame(height: 8)
                }
            }
            .clipShape(shape) // keeps the next-key bar inside the key's rounded corners
            .overlay(shape.stroke(wrong.contains(pitch) ? PP.mistake : PP.inkStaff.opacity(0.35),
                                  lineWidth: wrong.contains(pitch) ? 2 : 1))
            .overlay(alignment: .bottom) {
                VStack(spacing: 3) {
                    if let key = keyLabel(pitch) {
                        Text(key).font(.system(size: 13, weight: .bold, design: .monospaced))
                    }
                    Text(PitchName.of(pitch))
                        .font(.system(size: 10, weight: pitch % 12 == 0 ? .bold : .medium))
                }
                .foregroundColor(ink(pitch, black: false))
                .padding(.bottom, 14)
            }
    }

    private func blackKey(_ pitch: Int) -> some View {
        let shape = PPKeyShape(radius: 9)
        return shape
            .fill(fill(pitch, black: true))
            .overlay(alignment: .bottom) {
                if isNext(pitch) {
                    Rectangle().fill(PP.accent).frame(height: 6)
                }
            }
            .clipShape(shape)
            .overlay(wrong.contains(pitch) ? shape.stroke(PP.mistake, lineWidth: 2) : nil)
            .overlay(alignment: .bottom) {
                if let key = keyLabel(pitch) {
                    Text(key)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(ink(pitch, black: true))
                        .padding(.bottom, 10)
                }
            }
    }
}
#endif
