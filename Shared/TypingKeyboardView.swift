import SwiftUI

/// Used by the keyboard extension and the interactive keyboard settings preview.
struct TypingKeyboardView<Toolbar: View, Globe: View>: View {
  @ObservedObject var model: TypingKeyboardModel
  var scale: CGFloat = 1
  var inputDisabled = false
  var returnLabel = "return"
  let onInsert: (String) -> Void
  let onSpace: () -> Void
  let onDelete: () -> Void
  let onMoveCursor: (Int) -> Void
  let onLanguageChange: (KeyboardLanguage) -> Void
  /// Called on every key press (letters, space, delete, shift, return…), e.g. for haptics.
  var onKeyPress: () -> Void = {}
  @ViewBuilder let toolbar: () -> Toolbar
  @ViewBuilder let globe: () -> Globe
  @State private var showsLanguages = false
  @State private var accentKey: String?
  /// Held, not observed: the finger path changes on every touch move, and only
  /// the trail view redraws for it, not the whole keyboard.
  @State private var swipe = SwipeTracker()
  @State private var lexicon: SwipeLexicon?
  @State private var personalLexicon: SwipeLexicon?
  /// The word before the last swiped word, for learning which word follows which.
  @State private var swipePrevious: String?
  @State private var contextRankTask: Task<Void, Never>?

  var body: some View {
    VStack(spacing: 6 * self.scale) {
      HStack(spacing: 12) {
        Button {
          self.showsLanguages.toggle()
          self.accentKey = nil
        } label: {
          HStack(spacing: 4) {
            Text(verbatim: self.model.language.shortName).fontWeight(.semibold)
            Image(systemName: self.showsLanguages ? "chevron.up" : "chevron.down").font(.caption2)
          }
          .frame(minWidth: 56, minHeight: 44 * self.scale)
          .contentShape(Rectangle())
        }
        .accessibilityLabel("Keyboard language")
        .accessibilityValue(self.model.language.name)
        .accessibilityIdentifier("typing.languages")
        Button {
          self.pressKey()
          self.model.oneHanded = self.model.oneHanded == .off ? .right : .off
        } label: {
          Image(systemName: self.model.oneHanded == .off ? "keyboard.onehanded.right" : "keyboard")
            .frame(minWidth: 36, minHeight: 44 * self.scale)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(self.model.oneHanded == .off ? "One-handed keyboard" : "Full width keyboard")
        .accessibilityIdentifier("typing.oneHanded.toggle")
        if self.model.swipeSuggestions.isEmpty {
          self.toolbar()
        } else {
          self.swipeSuggestionBar
        }
      }
      .font(.system(size: 15 * self.scale))
      .padding(.horizontal, 6 * self.scale)
      .frame(height: 44 * self.scale)

      if self.showsLanguages {
        self.languagePicker
      } else {
        self.oneHandedContainer {
        Group {
          if let key = self.accentKey { self.accentPicker(key) }
          else { self.characterRow(self.model.rows[0]) }
          self.characterRow(self.model.rows[1])
            .padding(.horizontal, self.model.language == .english && self.model.page == .letters ? 14 * self.scale : 0)
          HStack(spacing: 5 * self.scale) {
            Button {
              self.pressKey()
              if self.model.page == .letters { self.model.tapShift() }
              else { self.model.page = self.model.page == .numbers ? .symbols : .numbers }
            } label: {
              if self.model.page == .letters {
                Image(systemName: self.model.shift == .locked ? "capslock.fill" : self.model.shift == .once ? "shift.fill" : "shift")
              } else { Text(self.model.page == .numbers ? "#+=" : "123").font(.system(size: 14 * self.scale)) }
            }
            .buttonStyle(TypingKeyStyle(height: 44 * self.scale, secondary: true))
            .frame(width: 37 * self.scale)
            .accessibilityLabel(self.model.page == .letters ? "Shift" : "More symbols")
            .accessibilityValue(self.model.shift == .locked ? "Caps Lock" : self.model.shift == .once ? "Uppercase" : "Lowercase")
            .accessibilityIdentifier("typing.shift")
            self.characterRow(self.model.rows[2])
            RepeatingDeleteKey(height: 44 * self.scale) { self.deleteKey() }
              .frame(width: 37 * self.scale)
          }
          HStack(spacing: 5 * self.scale) {
            Button(self.model.page == .letters ? "123" : "ABC") {
              self.pressKey()
              self.model.page = self.model.page == .letters ? .numbers : .letters
            }
            .font(.system(size: 15 * self.scale))
            .buttonStyle(TypingKeyStyle(height: 44 * self.scale, secondary: true))
            .frame(width: 42 * self.scale)
            .accessibilityIdentifier("typing.numbers")
            self.globe().frame(width: 36 * self.scale, height: 44 * self.scale)
            self.characterKey(",")
              .frame(width: 26 * self.scale)
            TypingSpaceKey(
              height: 44 * self.scale,
              onSpace: { self.learnTypedWord(); self.pressKey(); self.onSpace() },
              onMoveCursor: { self.pressKey(); self.onMoveCursor($0) },
            )
            self.characterKey(".")
              .frame(width: 26 * self.scale)
            Button { self.pressKey(); self.onInsert("\n") } label: {
              Text(verbatim: self.returnLabel).font(.system(size: 14 * self.scale))
                .lineLimit(1).minimumScaleFactor(0.7)
            }
            .buttonStyle(TypingKeyStyle(height: 44 * self.scale, secondary: true))
            .frame(width: 62 * self.scale)
            .accessibilityLabel("Return")
            .accessibilityIdentifier("typing.return")
          }
        }
        .disabled(self.inputDisabled)
        }
      }
    }
    .padding(.horizontal, 4 * self.scale)
    .padding(.vertical, 6 * self.scale)
    .frame(maxWidth: 900)
    .frame(maxWidth: .infinity)
    .onChange(of: self.model.page) { _, _ in
      self.accentKey = nil
      self.model.clearSwipe()
    }
    .task(id: self.model.language) {
      self.model.clearSwipe()
      let language = self.model.language
      self.lexicon = nil
      let lexicon = await Task.detached(priority: .utility) { SwipeLexicon.load(language) }.value
      self.lexicon = lexicon
      self.refreshPersonalLexicon()
    }
  }

  // MARK: Keys

  private func pressKey() {
    self.onKeyPress()
    self.model.clearSwipe()
  }

  private func typeKey(_ key: String) {
    self.model.clearSwipe()
    self.onInsert(self.model.consume(key))
  }


  /// Delete removes a just-swiped word in one go, like Gboard; otherwise one character.
  private func deleteKey() {
    self.onKeyPress()
    if let word = self.model.lastSwipeWord {
      // Deleting a swiped word right away means it was the wrong word.
      SwipeMemory.shared.learn(word, after: self.swipePrevious, language: self.model.language, weight: -1)
      self.contextRankTask?.cancel()
      for _ in word { self.onDelete() }
      self.model.clearSwipe()
    } else {
      self.onDelete()
    }
  }

  /// A word finished with the space bar is remembered, so names and slang become swipeable.
  private func learnTypedWord() {
    guard self.model.lastSwipeWord == nil, let context = self.model.contextBefore, context.last?.isLetter == true else { return }
    let words = context.split(whereSeparator: { !$0.isLetter })
    guard let word = words.last else { return }
    let previous = words.count > 1 ? String(words[words.count - 2]).lowercased(with: self.model.language.locale) : nil
    SwipeMemory.shared.learn(String(word), after: previous, language: self.model.language)
  }

  private func refreshPersonalLexicon() {
    guard let lexicon = self.lexicon else { return }
    let extra = SwipeMemory.shared.extraWords(language: self.model.language, excluding: lexicon)
    self.personalLexicon = extra.isEmpty ? nil : SwipeLexicon(language: self.model.language, words: extra, rankOffset: 500)
  }

  // MARK: Swipe typing



  private var letterKeys: Set<String> { Set(self.model.language.rows.joined()) }

  /// The letter key area's single touch handler: tap to type (on lift, like the
  /// system keyboard), hold for accents, or slide to swipe-type a word.
  private var keyTouchGesture: some Gesture {
    DragGesture(minimumDistance: 0, coordinateSpace: .named(typingKeySpace))
      .onChanged { value in self.touchChanged(value) }
      .onEnded { value in self.touchEnded(value) }
  }

  private func key(at point: CGPoint) -> String? {
    let frames = self.swipe.keyFrames
    if let hit = frames.first(where: { $0.value.contains(point) }) { return hit.key }
    // Between keys: take the nearest one within half a key.
    let nearest = frames.min { hypot($0.value.midX - point.x, $0.value.midY - point.y) < hypot($1.value.midX - point.x, $1.value.midY - point.y) }
    guard let nearest, hypot(nearest.value.midX - point.x, nearest.value.midY - point.y) < nearest.value.width else { return nil }
    return nearest.key
  }

  private func touchChanged(_ value: DragGesture.Value) {
    let tracker = self.swipe
    if value.startLocation != tracker.start {
      // A new touch (or a previous one iOS cancelled without ending).
      tracker.reset()
      tracker.start = value.startLocation
      guard !self.inputDisabled, let key = self.key(at: value.startLocation) else {
        tracker.touchKey = nil
        return
      }
      tracker.touchKey = key
      tracker.press.pressedKey = key
      self.onKeyPress()
      self.scheduleAccents(for: key, touch: value.startLocation)
      return
    }
    guard let touchKey = tracker.touchKey, !tracker.accentsShown else { return }
    if tracker.isSwiping {
      tracker.add(value.location)
      return
    }
    let width = tracker.keyFrames[touchKey]?.width ?? 30
    if self.model.page == .letters, self.lexicon != nil, self.letterKeys.contains(touchKey),
       hypot(value.translation.width, value.translation.height) > width * 0.8 {
      tracker.accentTask?.cancel()
      tracker.press.pressedKey = nil
      tracker.begin(at: value.startLocation, to: value.location)
      self.onKeyPress()
    } else if let current = self.key(at: value.location), current != tracker.press.pressedKey {
      tracker.press.pressedKey = current
    }
  }

  private func touchEnded(_ value: DragGesture.Value) {
    let tracker = self.swipe
    tracker.accentTask?.cancel()
    defer {
      tracker.start = nil
      tracker.touchKey = nil
      tracker.accentsShown = false
      tracker.press.pressedKey = nil
    }
    guard let touchKey = tracker.touchKey, !tracker.accentsShown else { return }
    if tracker.isSwiping {
      let path = tracker.path
      tracker.finish()
      self.finishSwipe(path)
      return
    }
    self.typeKey(self.key(at: value.location) ?? touchKey)
  }

  private func scheduleAccents(for key: String, touch: CGPoint) {
    let tracker = self.swipe
    guard self.model.page == .letters, !self.model.language.alternatives(for: key).isEmpty else { return }
    tracker.accentTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(400))
      guard !Task.isCancelled, tracker.start == touch, !tracker.isSwiping else { return }
      tracker.accentsShown = true
      tracker.press.pressedKey = nil
      self.accentKey = key
    }
  }

  private var swipeTrail: some View {
    SwipeTrailView(tracker: self.swipe, lineWidth: 7 * self.scale).allowsHitTesting(false)
  }

  private func finishSwipe(_ path: [CGPoint]) {
    guard let lexicon = self.lexicon else { return }
    let letters = self.swipe.keyFrames.filter { self.letterKeys.contains($0.key) }
    guard let size = letters.first?.value.size else { return }
    var centers: [Character: CGPoint] = [:]
    for (key, frame) in letters {
      if let character = key.first { centers[character] = CGPoint(x: frame.midX, y: frame.midY) }
    }
    let language = self.model.language
    let previous = SwipeMemory.previousWord(in: self.model.contextBefore, locale: language.locale)
    let snapshot = SwipeMemory.shared.snapshot(language: language)
    let personal = self.personalLexicon
    let decoder = SwipeDecoder(keyCenters: centers, keySize: size)
    // Decode off the main thread so typing and the trail never stall.
    Task {
      let scored = await Task.detached(priority: .userInitiated) { () -> [(word: String, cost: CGFloat)] in
        let boost: (String) -> CGFloat = { snapshot.boost($0, after: previous) }
        var scored = decoder.scored(for: path, in: lexicon, boost: boost)
        if let personal {
          scored += decoder.scored(for: path, in: personal, boost: boost)
          scored.sort { $0.cost < $1.cost }
        }
        return Array(scored.prefix(12))
      }.value
      self.insertSwipe(scored, previous: previous)
    }
  }

  private func insertSwipe(_ scored: [(word: String, cost: CGFloat)], previous: String?) {
    let language = self.model.language
    let memory = SwipeMemory.shared
    var seen = Set<String>()
    let ranked = scored.filter { seen.insert($0.word).inserted }.prefix(4)
    let candidates = ranked.map(\.word)
    guard let best = candidates.first else { return }
    self.onKeyPress()
    let needsSpace = self.model.swipeNeedsLeadingSpace
    let word = self.model.casedSwipeWord(best)
    self.onInsert((needsSpace ? " " : "") + word)
    self.model.lastSwipeWord = word
    self.model.swipeSuggestions = candidates.dropFirst().map { self.model.matchCase($0, to: word) }
    self.swipePrevious = previous
    memory.learn(best, after: previous, language: language)
    self.askContextModel(ranked: Array(ranked), inserted: word, previous: previous)
  }

  /// When the top words are close, let the on-device AI model pick using the
  /// sentence so far; if it prefers another word, swap it in (unless you have moved on).
  private func askContextModel(ranked: [(word: String, cost: CGFloat)], inserted: String, previous: String?) {
    self.contextRankTask?.cancel()
    guard ranked.count > 1, let context = self.model.contextBefore, !context.trimmingCharacters(in: .whitespaces).isEmpty else { return }
    let close = ranked.filter { $0.cost - ranked[0].cost < 0.6 }.map(\.word)
    // The on-device model costs real battery; skip it while you swipe in quick succession.
    guard close.count > 1, Date().timeIntervalSince(self.swipe.lastContextRequest) > 1.2 else { return }
    self.swipe.lastContextRequest = Date()
    let language = self.model.language
    let before = String(context.dropLast(inserted.count))
    self.contextRankTask = Task { @MainActor in
      guard
        let choice = await SwipeContextRanker.choose(context: before, candidates: close, language: language),
        !Task.isCancelled, self.model.lastSwipeWord == inserted,
        choice.lowercased(with: language.locale) != inserted.lowercased(with: language.locale)
      else { return }
      self.replaceSwipedWord(with: self.model.matchCase(choice, to: inserted), learn: false)
    }
  }

  private var swipeSuggestionBar: some View {
    HStack(spacing: 4) {
      ForEach(self.model.swipeSuggestions, id: \.self) { suggestion in
        Button {
          self.replaceSwipedWord(with: suggestion)
        } label: {
          Text(verbatim: suggestion)
            .lineLimit(1).minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, minHeight: 44 * self.scale)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("typing.suggestion.\(suggestion)")
      }
    }
    .frame(maxWidth: .infinity)
  }

  private func replaceSwipedWord(with suggestion: String, learn: Bool = true) {
    guard let current = self.model.lastSwipeWord else { return }
    if learn {
      self.contextRankTask?.cancel()
      self.onKeyPress()
      SwipeMemory.shared.learn(suggestion, after: self.swipePrevious, language: self.model.language, weight: 3)
      SwipeMemory.shared.learn(current, after: self.swipePrevious, language: self.model.language, weight: -2)
    }
    for _ in current { self.onDelete() }
    self.onInsert(suggestion)
    var suggestions = self.model.swipeSuggestions.filter { $0 != suggestion }
    suggestions.insert(current, at: 0)
    self.model.swipeSuggestions = Array(suggestions.prefix(3))
    self.model.lastSwipeWord = suggestion
  }

  private var languagePicker: some View {
    VStack(spacing: 6 * self.scale) {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5 * self.scale), count: 4), spacing: 6 * self.scale) {
      ForEach(KeyboardLanguage.allCases) { language in
        Button {
          self.model.language = language
          self.model.page = .letters
          self.showsLanguages = false
          self.onLanguageChange(language)
        } label: {
          Text(verbatim: language.name)
            .font(.system(size: 12 * self.scale, weight: language == self.model.language ? .bold : .regular))
            .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.75)
        }
        .buttonStyle(TypingKeyStyle(height: 44 * self.scale, secondary: language == self.model.language))
        .accessibilityIdentifier("typing.language.\(language.rawValue)")
      }
    }
      HStack(spacing: 5 * self.scale) {
        self.oneHandedOption(.left, symbol: "keyboard.onehanded.left", label: "One-handed, left")
        self.oneHandedOption(.off, symbol: "keyboard", label: "Full width")
        self.oneHandedOption(.right, symbol: "keyboard.onehanded.right", label: "One-handed, right")
      }
    }
    .frame(height: 194 * self.scale)
  }

  private func oneHandedOption(_ mode: OneHandedMode, symbol: String, label: LocalizedStringKey) -> some View {
    Button {
      self.pressKey()
      self.model.oneHanded = mode
      self.showsLanguages = false
    } label: {
      Image(systemName: symbol).font(.system(size: 20 * self.scale))
    }
    .buttonStyle(TypingKeyStyle(height: 44 * self.scale, secondary: self.model.oneHanded == mode))
    .accessibilityLabel(label)
    .accessibilityAddTraits(self.model.oneHanded == mode ? .isSelected : [])
    .accessibilityIdentifier("typing.oneHanded.\(mode.rawValue)")
  }

  /// In one-handed mode the keys take most of the width on one side; the free
  /// strip holds a button to move the keys across and one to go back to full width.
  @ViewBuilder
  private func oneHandedContainer(@ViewBuilder _ keys: () -> some View) -> some View {
    let mode = self.model.oneHanded
    let keyStack = VStack(spacing: 6 * self.scale) { keys() }
      .coordinateSpace(.named(typingKeySpace))
      .onPreferenceChange(TypingKeyFramesKey.self) { self.swipe.keyFrames = $0 }
      .contentShape(Rectangle())
      .gesture(self.keyTouchGesture)
      .overlay { self.swipeTrail }
    if mode == .off {
      keyStack
    } else {
      GeometryReader { geometry in
        HStack(spacing: 0) {
          if mode == .right { self.oneHandedControls(moveTo: .left) }
          keyStack.frame(width: geometry.size.width * OneHandedMode.keyWidthFraction)
          if mode == .left { self.oneHandedControls(moveTo: .right) }
        }
      }
      .frame(height: (4 * 44 + 3 * 6) * self.scale)
    }
  }

  private func oneHandedControls(moveTo side: OneHandedMode) -> some View {
    VStack(spacing: 24 * self.scale) {
      Button { self.model.oneHanded = .off } label: {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
          .frame(maxWidth: .infinity, minHeight: 44 * self.scale)
          .contentShape(Rectangle())
      }
      .accessibilityLabel("Full width keyboard")
      .accessibilityIdentifier("typing.oneHanded.expand")
      Button { self.model.oneHanded = side } label: {
        Image(systemName: side == .left ? "chevron.left" : "chevron.right")
          .frame(maxWidth: .infinity, minHeight: 44 * self.scale)
          .contentShape(Rectangle())
      }
      .accessibilityLabel(side == .left ? "Move keyboard left" : "Move keyboard right")
      .accessibilityIdentifier("typing.oneHanded.move")
    }
    .font(.system(size: 18 * self.scale, weight: .medium))
    .foregroundStyle(.secondary)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func accentPicker(_ key: String) -> some View {
    HStack(spacing: 5 * self.scale) {
      ForEach([key] + self.model.language.alternatives(for: key), id: \.self) { variant in
        Button(self.model.displayed(variant)) {
          self.pressKey()
          self.onInsert(self.model.consume(variant))
          self.accentKey = nil
        }
        .buttonStyle(TypingKeyStyle(height: 44 * self.scale))
      }
      Button { self.accentKey = nil } label: { Image(systemName: "xmark") }
        .buttonStyle(TypingKeyStyle(height: 44 * self.scale, secondary: true))
        .accessibilityLabel("Close accents")
    }
    .font(.system(size: 23 * self.scale))
  }

  private func characterRow(_ keys: [String]) -> some View {
    HStack(spacing: 5 * self.scale) {
      ForEach(keys, id: \.self) { self.characterKey($0) }
    }
  }

  @ViewBuilder
  private func characterKey(_ key: String) -> some View {
    // Visual only: one touch handler on the key area (see `keyTouchGesture`) handles
    // taps, swipes and long-press accents, so no per-key gesture can block a swipe.
    CharacterKeyView(key: key, label: self.model.displayed(key), height: 44 * self.scale,
                     fontSize: 23 * self.scale, press: self.swipe.press)
      .background {
        GeometryReader { geometry in
          Color.clear.preference(key: TypingKeyFramesKey.self, value: [key: geometry.frame(in: .named(typingKeySpace))])
        }
      }
      .accessibilityElement()
      .accessibilityLabel(self.model.displayed(key))
      .accessibilityAddTraits(.isButton)
      .accessibilityIdentifier("typing.key.\(key)")
      .accessibilityAction { self.typeKey(key) }
  }

}

private struct TypingKeyStyle: ButtonStyle {
  let height: CGFloat
  var secondary = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(.primary)
      .frame(maxWidth: .infinity, minHeight: self.height, maxHeight: self.height)
      .background(TypingKeyFill(pressed: configuration.isPressed, secondary: self.secondary))
      .contentShape(Rectangle())
  }
}

private struct TypingKeyFill: View {
  var pressed = false
  var secondary = false
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    RoundedRectangle(cornerRadius: 6)
      .fill(Color(uiColor: self.pressed ? .systemGray2 : self.secondary ? .systemGray3 : self.colorScheme == .dark ? .systemGray4 : .white))
      .shadow(color: .black.opacity(0.2), radius: 0, y: 1)
  }
}

private struct RepeatingDeleteKey: View {
  let height: CGFloat
  let action: () -> Void
  @State private var repeatTask: Task<Void, Never>?
  @State private var pressed = false
  @Environment(\.isEnabled) private var enabled

  var body: some View {
    Image(systemName: "delete.left")
      .font(.system(size: 20)).frame(maxWidth: .infinity).frame(height: self.height)
      .background(TypingKeyFill(pressed: self.pressed, secondary: true))
      .contentShape(Rectangle())
      .gesture(DragGesture(minimumDistance: 0).onChanged { _ in
        guard self.enabled, !self.pressed else { return }
        self.pressed = true
        self.action()
        self.repeatTask = Task { @MainActor in
          do {
            try await Task.sleep(for: .milliseconds(400))
            while !Task.isCancelled {
              self.action()
              try await Task.sleep(for: .milliseconds(75))
            }
          } catch { }
        }
      }.onEnded { _ in self.stopRepeating() })
      .onChange(of: self.enabled) { _, enabled in if !enabled { self.stopRepeating() } }
      .onDisappear { self.stopRepeating() }
      .accessibilityLabel("Delete")
      .accessibilityIdentifier("typing.delete")
      .accessibilityAddTraits(.isButton)
      .accessibilityAction { self.action() }
  }

  private func stopRepeating() {
    self.repeatTask?.cancel()
    self.repeatTask = nil
    self.pressed = false
  }
}

private struct TypingSpaceKey: View {
  let height: CGFloat
  let onSpace: () -> Void
  let onMoveCursor: (Int) -> Void
  @State private var pressed = false
  @State private var lastOffset = 0
  @State private var moved = false
  @Environment(\.isEnabled) private var enabled

  var body: some View {
    Text("space").font(.system(size: 15))
      .frame(maxWidth: .infinity).frame(height: self.height)
      .background(TypingKeyFill(pressed: self.pressed))
      .contentShape(Rectangle())
      .gesture(DragGesture(minimumDistance: 0).onChanged { value in
        guard self.enabled else { return }
        self.pressed = true
        let offset = Int(value.translation.width / 12)
        if offset != self.lastOffset {
          self.moved = true
          self.onMoveCursor(offset - self.lastOffset)
          self.lastOffset = offset
        }
      }.onEnded { _ in
        if self.enabled, !self.moved { self.onSpace() }
        self.pressed = false
        self.moved = false
        self.lastOffset = 0
      })
      .accessibilityLabel("Space")
      .accessibilityIdentifier("typing.space")
      .accessibilityAddTraits(.isButton)
      .accessibilityAction { self.onSpace() }
  }
}

private struct TypingKeyFramesKey: PreferenceKey {
  static let defaultValue: [String: CGRect] = [:]
  static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
    value.merge(nextValue()) { $1 }
  }
}

private let typingKeySpace = "typingKeys"

/// Finger path for the swipe trail. Only `SwipeTrailView` observes it.
@MainActor
final class SwipeTracker: ObservableObject {
  @Published private(set) var path: [CGPoint] = []
  private(set) var isSwiping = false
  var start: CGPoint?
  var lastContextRequest = Date.distantPast
  var touchKey: String?
  var accentsShown = false
  var accentTask: Task<Void, Never>?
  /// Which key shows as pressed; observed only by the key views.
  let press = KeyPressState()
  /// Letter key frames in the key area's coordinates; not published.
  var keyFrames: [String: CGRect] = [:]

  func begin(at start: CGPoint, to point: CGPoint) {
    self.isSwiping = true
    self.path = [start, point]
  }

  func add(_ point: CGPoint) {
    // Skip points closer than 3 pt; the decoder resamples anyway.
    if let last = self.path.last, hypot(point.x - last.x, point.y - last.y) < 3 { return }
    self.path.append(point)
  }

  func finish() {
    self.isSwiping = false
    withAnimation(.easeOut(duration: 0.2)) { self.path = [] }
  }

  func reset() {
    self.isSwiping = false
    if !self.path.isEmpty { self.path = [] }
  }
}

private struct SwipeTrailView: View {
  @ObservedObject var tracker: SwipeTracker
  let lineWidth: CGFloat

  var body: some View {
    Canvas { context, _ in
      guard self.tracker.path.count > 1 else { return }
      var path = Path()
      path.addLines(self.tracker.path)
      context.stroke(path, with: .color(.accentColor.opacity(0.55)),
                     style: StrokeStyle(lineWidth: self.lineWidth, lineCap: .round, lineJoin: .round))
    }
  }
}

@MainActor
final class KeyPressState: ObservableObject {
  @Published var pressedKey: String?
}

private struct CharacterKeyView: View {
  let key: String
  let label: String
  let height: CGFloat
  let fontSize: CGFloat
  @ObservedObject var press: KeyPressState

  var body: some View {
    Text(verbatim: self.label)
      .font(.system(size: self.fontSize))
      .foregroundStyle(.primary)
      .frame(maxWidth: .infinity, minHeight: self.height, maxHeight: self.height)
      .background(TypingKeyFill(pressed: self.press.pressedKey == self.key))
      .allowsHitTesting(false)
  }
}
