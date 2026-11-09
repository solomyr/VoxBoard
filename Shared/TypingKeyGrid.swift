import SwiftUI
import UIKit

/// The three character rows (with shift and delete), drawn and handled in UIKit
/// the way Gboard does it: keys are layers drawn once, one touch handler covers
/// the whole area and picks the key under the finger, and a touch redraws only
/// the key it presses or the swipe trail. Nothing in SwiftUI changes per touch.
struct TypingKeyGrid: UIViewRepresentable {
  struct Config: Equatable {
    var rows: [[String]] = []
    var labels: [[String]] = []
    var lettersPage = true
    /// SF Symbol for shift on the letters page, or text ("#+=", "123") on the others.
    var shiftSymbol = "shift"
    var shiftText: String?
    var shiftLabel = "Shift"
    var shiftValue = ""
    var rowInsets: [CGFloat] = [0, 0, 0]
    var scale: CGFloat = 1
    var disabled = false
    var swipeEnabled = false
    var accentKeys: Set<String> = []
    /// The accent picker covers the first row while it is open.
    var hidesFirstRow = false

    static func height(scale: CGFloat) -> CGFloat { 3 * 44 * scale + 2 * 6 * scale }
  }

  struct Handlers {
    var keyDown: () -> Void = {}
    var tap: (String) -> Void = { _ in }
    var shift: () -> Void = {}
    var delete: () -> Void = {}
    var longPress: (String) -> Void = { _ in }
    var swipeBegan: () -> Void = {}
    var swipe: (_ path: [CGPoint], _ centers: [Character: CGPoint], _ keySize: CGSize) -> Void = { _, _, _ in }
  }

  var config: Config
  var handlers: Handlers

  func makeUIView(context _: Context) -> TypingKeyGridView {
    let view = TypingKeyGridView()
    view.handlers = self.handlers
    view.apply(self.config)
    return view
  }

  func updateUIView(_ view: TypingKeyGridView, context _: Context) {
    view.handlers = self.handlers
    view.apply(self.config)
  }
}

final class TypingKeyGridView: UIView {
  var handlers = TypingKeyGrid.Handlers()

  override init(frame: CGRect) {
    super.init(frame: frame)
    self.isMultipleTouchEnabled = true
    self.isAccessibilityElement = false
    // Fully transparent pixels get no touches inside a keyboard extension.
    self.backgroundColor = UIColor(white: 0, alpha: 0.01)
    self.trail.fillColor = nil
    self.trail.lineCap = .round
    self.trail.lineJoin = .round
    self.trail.zPosition = 10
    self.layer.addSublayer(self.trail)
    // Keep touches that start on the keys from turning into a scroll or a
    // "swipe back" in the app's settings preview, which would cancel the swipe.
    let claim = TouchClaimRecognizer()
    claim.delegate = self.claimDelegate
    self.addGestureRecognizer(claim)
    self.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: TypingKeyGridView, _: UITraitCollection) in
      view.updateColors()
    }
  }

  private let claimDelegate = TouchClaimDelegate()

  @available(*, unavailable)
  required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

  // MARK: Configuration

  private var config = TypingKeyGrid.Config()
  private var keys: [Key] = []

  func apply(_ config: TypingKeyGrid.Config) {
    guard config != self.config else { return }
    let old = self.config
    self.config = config
    if config.rows != old.rows || config.scale != old.scale || self.keys.isEmpty {
      self.rebuildKeys()
    } else {
      self.updateLabels()
    }
    if config.rowInsets != old.rowInsets || config.hidesFirstRow != old.hidesFirstRow { self.setNeedsLayout() }
    if config.disabled != old.disabled || config.hidesFirstRow != old.hidesFirstRow { self.updateColors() }
    if config.disabled || config.hidesFirstRow != old.hidesFirstRow { self.cancelAllTouches() }
    self.updateAccessibility()
  }

  private func rebuildKeys() {
    self.cancelAllTouches()
    for key in self.keys {
      key.background.removeFromSuperlayer()
      key.content.removeFromSuperview()
    }
    self.keys = []
    for (row, ids) in self.config.rows.enumerated() {
      if row == 2 { self.keys.append(self.makeKey(.shift, id: "shift", row: row)) }
      for id in ids { self.keys.append(self.makeKey(.character, id: id, row: row)) }
      if row == 2 { self.keys.append(self.makeKey(.delete, id: "delete", row: row)) }
    }
    self.updateLabels()
    self.updateColors()
    self.setNeedsLayout()
  }

  private func makeKey(_ kind: Key.Kind, id: String, row: Int) -> Key {
    let background = CALayer()
    background.cornerRadius = 6
    background.shadowColor = UIColor.black.cgColor
    background.shadowOpacity = 0.2
    background.shadowRadius = 0
    background.shadowOffset = CGSize(width: 0, height: 1)
    self.layer.insertSublayer(background, below: self.trail)
    let content: UIView
    switch kind {
    case .character:
      let label = UILabel()
      label.font = .systemFont(ofSize: 23 * self.config.scale)
      label.textAlignment = .center
      label.adjustsFontSizeToFitWidth = true
      label.minimumScaleFactor = 0.6
      content = label
    case .shift, .delete:
      let image = UIImageView()
      image.contentMode = .center
      image.tintColor = .label
      content = image
    }
    content.isUserInteractionEnabled = false
    self.addSubview(content)
    let element = KeyElement(accessibilityContainer: self)
    element.accessibilityTraits = .button
    return Key(kind: kind, id: id, row: row, background: background, content: content, element: element)
  }

  private func updateLabels() {
    let scale = self.config.scale
    var index: [Int: Int] = [:]
    for key in self.keys {
      switch key.kind {
      case .character:
        let column = index[key.row, default: 0]
        index[key.row] = column + 1
        let text = self.config.labels[safe: key.row]?[safe: column] ?? key.id
        (key.content as? UILabel)?.text = text
        key.element.accessibilityLabel = text
        key.element.accessibilityIdentifier = "typing.key.\(key.id)"
      case .shift:
        let image = key.content as? UIImageView
        if let text = self.config.shiftText {
          image?.image = Self.textImage(text, size: 14 * scale)
        } else {
          image?.image = UIImage(systemName: self.config.shiftSymbol,
                                 withConfiguration: UIImage.SymbolConfiguration(pointSize: 17 * scale))
        }
        key.element.accessibilityLabel = self.config.shiftLabel
        key.element.accessibilityValue = self.config.shiftValue
        key.element.accessibilityIdentifier = "typing.shift"
      case .delete:
        (key.content as? UIImageView)?.image = UIImage(systemName: "delete.left",
                                                       withConfiguration: UIImage.SymbolConfiguration(pointSize: 20 * scale))
        key.element.accessibilityLabel = "Delete"
        key.element.accessibilityIdentifier = "typing.delete"
      }
    }
  }

  private static func textImage(_ text: String, size: CGFloat) -> UIImage {
    let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: size), .foregroundColor: UIColor.black]
    let bounds = (text as NSString).size(withAttributes: attributes)
    let image = UIGraphicsImageRenderer(size: bounds).image { _ in (text as NSString).draw(at: .zero, withAttributes: attributes) }
    return image.withRenderingMode(.alwaysTemplate)
  }

  // MARK: Layout

  override func layoutSubviews() {
    super.layoutSubviews()
    let scale = self.config.scale
    let height = 44 * scale, rowGap = 6 * scale, gap = 5 * scale, side = 37 * scale
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for row in 0 ..< 3 {
      let inset = self.config.rowInsets[safe: row] ?? 0
      let rowKeys = self.keys.filter { $0.row == row }
      let characters = rowKeys.filter { $0.kind == .character }.count
      var width = self.bounds.width - 2 * inset
      if row == 2 { width -= 2 * (side + gap) }
      let keyWidth = characters > 0 ? (width - CGFloat(characters - 1) * gap) / CGFloat(characters) : 0
      var x = inset
      let y = CGFloat(row) * (height + rowGap)
      for key in rowKeys {
        let w = key.kind == .character ? keyWidth : side
        key.frame = CGRect(x: x, y: y, width: w, height: height)
        x += w + gap
        key.background.frame = key.frame
        key.background.shadowPath = UIBezierPath(roundedRect: key.background.bounds, cornerRadius: 6).cgPath
        key.content.frame = key.frame.insetBy(dx: 1, dy: 0)
        let hidden = row == 0 && self.config.hidesFirstRow
        key.background.isHidden = hidden
        key.content.isHidden = hidden
      }
    }
    self.trail.frame = self.bounds
    self.trail.lineWidth = 7 * scale
    CATransaction.commit()
    self.updateAccessibility()
  }

  override var intrinsicContentSize: CGSize {
    CGSize(width: UIView.noIntrinsicMetric, height: TypingKeyGrid.Config.height(scale: self.config.scale))
  }

  // MARK: Colors

  private func color(_ key: Key) -> UIColor {
    if key.pressed { return .systemGray2 }
    if key.kind != .character { return .systemGray3 }
    return self.traitCollection.userInterfaceStyle == .dark ? .systemGray4 : .white
  }

  private func updateColors() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let traits = self.traitCollection
    for key in self.keys {
      key.background.backgroundColor = self.color(key).resolvedColor(with: traits).cgColor
      key.content.alpha = self.config.disabled ? 0.4 : 1
      (key.content as? UILabel)?.textColor = .label
    }
    self.trail.strokeColor = self.tintColor.withAlphaComponent(0.55).resolvedColor(with: traits).cgColor
    CATransaction.commit()
  }

  override func tintColorDidChange() {
    super.tintColorDidChange()
    self.updateColors()
  }

  private func setPressed(_ key: Key?, _ pressed: Bool) {
    guard let key, key.pressed != pressed else { return }
    key.pressed = pressed
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    key.background.backgroundColor = self.color(key).resolvedColor(with: self.traitCollection).cgColor
    CATransaction.commit()
  }

  // MARK: Touches

  private final class TouchState {
    let key: Key?
    let start: CGPoint
    var swiping = false
    var path: [CGPoint] = []
    /// Already handled (rolled over, long-pressed, delete): lifting does nothing.
    var consumed = false
    var longPress: DispatchWorkItem?

    init(key: Key?, start: CGPoint) {
      self.key = key
      self.start = start
    }
  }

  private var touchStates: [ObjectIdentifier: TouchState] = [:]
  private var deleteTimer: Timer?
  private let trail = CAShapeLayer()

  private func key(at point: CGPoint) -> Key? {
    let scale = self.config.scale
    let rowHeight = 44 * scale + 6 * scale
    let row = min(2, max(0, Int((point.y + 3 * scale) / rowHeight)))
    if row == 0, self.config.hidesFirstRow { return nil }
    let rowKeys = self.keys.filter { $0.row == row }
    // Gaps belong to the nearest key, like Gboard: no dead space between keys.
    return rowKeys.min { abs($0.frame.midX - point.x) - $0.frame.width / 2 < abs($1.frame.midX - point.x) - $1.frame.width / 2 }
  }

  override func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent?) {
    guard !self.config.disabled else { return }
    for touch in touches {
      let point = touch.location(in: self)
      // A new finger finishes what the others were doing: a swipe ends and a
      // held key is typed now, so fast two-thumb typing keeps its order.
      for state in self.touchStates.values where !state.consumed {
        if state.swiping {
          self.finishSwipe(state)
        } else if let key = state.key, key.kind == .character {
          state.longPress?.cancel()
          state.consumed = true
          self.handlers.tap(key.id)
          self.setPressed(key, false)
        }
      }
      let key = self.key(at: point)
      let state = TouchState(key: key, start: point)
      self.touchStates[ObjectIdentifier(touch)] = state
      guard let key else { continue }
      self.handlers.keyDown()
      self.setPressed(key, true)
      switch key.kind {
      case .delete:
        state.consumed = true
        self.handlers.delete()
        self.startDeleteRepeat()
      case .character where self.config.lettersPage && self.config.accentKeys.contains(key.id):
        let work = DispatchWorkItem { [weak self, weak state] in
          guard let self, let state, !state.swiping, !state.consumed else { return }
          state.consumed = true
          self.setPressed(key, false)
          self.handlers.longPress(key.id)
        }
        state.longPress = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
      default:
        break
      }
    }
  }

  override func touchesMoved(_ touches: Set<UITouch>, with _: UIEvent?) {
    for touch in touches {
      guard let state = self.touchStates[ObjectIdentifier(touch)], !state.consumed || state.swiping else { continue }
      let point = touch.location(in: self)
      if state.swiping {
        if let last = state.path.last, hypot(point.x - last.x, point.y - last.y) < 3 { continue }
        state.path.append(point)
        self.drawTrail(state.path)
        continue
      }
      guard
        self.config.swipeEnabled, let key = state.key, key.kind == .character,
        hypot(point.x - state.start.x, point.y - state.start.y) > key.frame.width * 0.8
      else { continue }
      state.swiping = true
      state.longPress?.cancel()
      self.setPressed(key, false)
      state.path = [state.start, point]
      self.trail.removeAllAnimations()
      self.trail.opacity = 1
      self.drawTrail(state.path)
      self.handlers.swipeBegan()
    }
  }

  override func touchesEnded(_ touches: Set<UITouch>, with _: UIEvent?) {
    self.end(touches, typing: true)
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with _: UIEvent?) {
    self.end(touches, typing: false)
  }

  private func end(_ touches: Set<UITouch>, typing: Bool) {
    for touch in touches {
      guard let state = self.touchStates.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
      state.longPress?.cancel()
      self.setPressed(state.key, false)
      if state.key?.kind == .delete { self.stopDeleteRepeat() }
      if state.swiping, !state.consumed {
        self.finishSwipe(state)
      } else if typing, !state.consumed, let key = state.key {
        switch key.kind {
        case .character: self.handlers.tap(key.id)
        case .shift: self.handlers.shift()
        case .delete: break
        }
      }
    }
  }

  private func cancelAllTouches() {
    for state in self.touchStates.values {
      state.longPress?.cancel()
      self.setPressed(state.key, false)
    }
    self.touchStates = [:]
    self.stopDeleteRepeat()
    self.trail.path = nil
  }

  private func finishSwipe(_ state: TouchState) {
    state.swiping = false
    state.consumed = true
    let letters = self.keys.filter { $0.kind == .character }
    var centers: [Character: CGPoint] = [:]
    for key in letters {
      if let character = key.id.first { centers[character] = CGPoint(x: key.frame.midX, y: key.frame.midY) }
    }
    if let size = letters.first?.frame.size, state.path.count > 1 {
      self.handlers.swipe(state.path, centers, size)
    }
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 1
    fade.toValue = 0
    fade.duration = 0.2
    self.trail.opacity = 0
    self.trail.add(fade, forKey: "fade")
  }

  private func drawTrail(_ points: [CGPoint]) {
    let path = CGMutablePath()
    path.addLines(between: points)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    self.trail.path = path
    CATransaction.commit()
  }

  private func startDeleteRepeat() {
    self.stopDeleteRepeat()
    let timer = Timer(timeInterval: 0.4, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        let repeating = Timer(timeInterval: 0.075, repeats: true) { [weak self] _ in
          MainActor.assumeIsolated { self?.handlers.delete() }
        }
        RunLoop.main.add(repeating, forMode: .common)
        self.deleteTimer = repeating
        self.handlers.delete()
      }
    }
    RunLoop.main.add(timer, forMode: .common)
    self.deleteTimer = timer
  }

  private func stopDeleteRepeat() {
    self.deleteTimer?.invalidate()
    self.deleteTimer = nil
  }

  // MARK: Accessibility (VoiceOver and UI tests see each key as a button)

  private func updateAccessibility() {
    var elements: [KeyElement] = []
    for key in self.keys where !(key.row == 0 && self.config.hidesFirstRow) {
      key.element.accessibilityFrameInContainerSpace = key.frame
      let action: () -> Void
      switch key.kind {
      case .character: action = { [weak self] in self?.handlers.tap(key.id) }
      case .shift: action = { [weak self] in self?.handlers.shift() }
      case .delete: action = { [weak self] in self?.handlers.delete() }
      }
      key.element.activate = action
      elements.append(key.element)
    }
    self.accessibilityElements = elements
  }
}

private final class Key {
  enum Kind { case character, shift, delete }

  let kind: Kind
  let id: String
  let row: Int
  let background: CALayer
  let content: UIView
  let element: KeyElement
  var frame = CGRect.zero
  var pressed = false

  init(kind: Kind, id: String, row: Int, background: CALayer, content: UIView, element: KeyElement) {
    self.kind = kind
    self.id = id
    self.row = row
    self.background = background
    self.content = content
    self.element = element
  }
}

private final class KeyElement: UIAccessibilityElement {
  var activate: () -> Void = {}

  override func accessibilityActivate() -> Bool {
    self.activate()
    return true
  }
}

/// Recognizes as soon as a finger lands on the keys and never cancels their
/// touches; scroll views must wait for it to fail, so they never steal a swipe.
private final class TouchClaimRecognizer: UIGestureRecognizer {
  override init(target: Any? = nil, action: Selector? = nil) {
    super.init(target: target, action: action)
    self.cancelsTouchesInView = false
    self.delaysTouchesBegan = false
    self.delaysTouchesEnded = false
  }

  override func touchesBegan(_: Set<UITouch>, with _: UIEvent) {
    if self.state == .possible { self.state = .began }
  }

  override func touchesMoved(_: Set<UITouch>, with _: UIEvent) {
    if self.state == .began || self.state == .changed { self.state = .changed }
  }

  override func touchesEnded(_: Set<UITouch>, with event: UIEvent) {
    self.finishIfIdle(event)
  }

  override func touchesCancelled(_: Set<UITouch>, with event: UIEvent) {
    self.finishIfIdle(event)
  }

  private func finishIfIdle(_ event: UIEvent) {
    let down = event.allTouches?.contains { $0.view === self.view && $0.phase != .ended && $0.phase != .cancelled } ?? false
    if !down { self.state = self.state == .possible ? .failed : .ended }
  }
}

private final class TouchClaimDelegate: NSObject, UIGestureRecognizerDelegate {
  /// Pans elsewhere in the window (a scroll view, the navigation "swipe back"
  /// that a left-to-right swipe would trigger) wait until the finger lifts.
  func gestureRecognizer(_ claim: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
    other is UIPanGestureRecognizer && other.view !== claim.view
  }

  func gestureRecognizer(_: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
    !(other is UIPanGestureRecognizer)
  }
}

private extension Array {
  subscript(safe index: Int) -> Element? { self.indices.contains(index) ? self[index] : nil }
}
