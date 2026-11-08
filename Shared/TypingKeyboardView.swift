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
  @State private var keyFrames: [String: CGRect] = [:]
  @State private var swipePath: [CGPoint] = []
  @State private var isSwiping = false
  @State private var swipeEndedAt = Date.distantPast
  @State private var lexicon: SwipeLexicon?

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
              onSpace: { self.pressKey(); self.onSpace() },
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
      self.lexicon = await Task.detached(priority: .utility) { SwipeLexicon.load(language) }.value
    }
  }

  // MARK: Keys

  private func pressKey() {
    self.onKeyPress()
    self.model.clearSwipe()
  }

  private func tapCharacter(_ key: String) {
    // The touch that ends a swipe can also complete a tap on the key under it.
    guard Date().timeIntervalSince(self.swipeEndedAt) > 0.3 else { return }
    self.pressKey()
    self.onInsert(self.model.consume(key))
  }

  /// Delete removes a just-swiped word in one go, like Gboard; otherwise one character.
  private func deleteKey() {
    self.onKeyPress()
    if let word = self.model.lastSwipeWord {
      for _ in word { self.onDelete() }
      self.model.clearSwipe()
    } else {
      self.onDelete()
    }
  }

  // MARK: Swipe typing



  private var letterKeys: Set<String> { Set(self.model.language.rows.joined()) }

  private var swipeGesture: some Gesture {
    DragGesture(minimumDistance: 8, coordinateSpace: .named(typingKeySpace))
      .onChanged { value in
        if self.isSwiping {
          self.swipePath.append(value.location)
          return
        }
        guard
          self.model.page == .letters, self.accentKey == nil, !self.inputDisabled, self.lexicon != nil,
          let start = self.keyFrames.first(where: { self.letterKeys.contains($0.key) && $0.value.contains(value.startLocation) }),
          hypot(value.translation.width, value.translation.height) > start.value.width * 0.8
        else { return }
        self.isSwiping = true
        self.swipePath = [value.startLocation, value.location]
      }
      .onEnded { _ in
        guard self.isSwiping else { return }
        self.isSwiping = false
        self.swipeEndedAt = Date()
        self.finishSwipe(self.swipePath)
        withAnimation(.easeOut(duration: 0.2)) { self.swipePath = [] }
      }
  }

  private var swipeTrail: some View {
    Canvas { context, _ in
      guard self.swipePath.count > 1 else { return }
      var path = Path()
      path.addLines(self.swipePath)
      context.stroke(path, with: .color(.accentColor.opacity(0.55)),
                     style: StrokeStyle(lineWidth: 7 * self.scale, lineCap: .round, lineJoin: .round))
    }
    .allowsHitTesting(false)
  }

  private func finishSwipe(_ path: [CGPoint]) {
    guard let lexicon = self.lexicon else { return }
    let letters = self.keyFrames.filter { self.letterKeys.contains($0.key) }
    guard let size = letters.first?.value.size else { return }
    var centers: [Character: CGPoint] = [:]
    for (key, frame) in letters {
      if let character = key.first { centers[character] = CGPoint(x: frame.midX, y: frame.midY) }
    }
    let candidates = SwipeDecoder(keyCenters: centers, keySize: size).candidates(for: path, in: lexicon)
    guard let best = candidates.first else { return }
    self.onKeyPress()
    let word = self.model.casedSwipeWord(best)
    self.onInsert((self.model.swipeNeedsLeadingSpace ? " " : "") + word)
    self.model.lastSwipeWord = word
    self.model.swipeSuggestions = candidates.dropFirst().map { self.model.matchCase($0, to: word) }
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

  private func replaceSwipedWord(with suggestion: String) {
    guard let current = self.model.lastSwipeWord else { return }
    self.onKeyPress()
    for _ in current { self.onDelete() }
    self.onInsert(suggestion)
    self.model.swipeSuggestions = self.model.swipeSuggestions.map { $0 == suggestion ? current : $0 }
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
      .onPreferenceChange(TypingKeyFramesKey.self) { self.keyFrames = $0 }
      .simultaneousGesture(self.swipeGesture)
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
    let alternatives = self.model.page == .letters ? self.model.language.alternatives(for: key) : []
    Group {
      if alternatives.isEmpty {
        Button { self.tapCharacter(key) } label: {
          Text(verbatim: self.model.displayed(key))
        }
      } else {
        Button { self.tapCharacter(key) } label: {
          Text(verbatim: self.model.displayed(key))
        }
        .highPriorityGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in self.accentKey = key })
      }
    }
    .font(.system(size: 23 * self.scale))
    .buttonStyle(TypingKeyStyle(height: 44 * self.scale))
    .background {
      GeometryReader { geometry in
        Color.clear.preference(key: TypingKeyFramesKey.self, value: [key: geometry.frame(in: .named(typingKeySpace))])
      }
    }
    .accessibilityLabel(self.model.displayed(key))
    .accessibilityIdentifier("typing.key.\(key)")
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
