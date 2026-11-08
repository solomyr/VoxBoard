import Testing

@Suite("Ready-to-send numeric facts")
struct ReadyToSendValidationTests {
  @Test(arguments: [
    ("meet at 18:30 with 2 books", "Meet at 18:30 with 2 books."),
    ("цена 12,50 лв", "Цена: 12,50 лв."),
    ("لا تتجاوز ٢٥", "لا تتجاوز ٢٥."),
    ("-12 degrees", "It is -12 degrees."),
    ("你好", "你好！"),
  ])
  func `formatting retains numeric facts`(input: (String, String)) {
    #expect(ReadyToSendValidation.preservesNumbers(original: input.0, edited: input.1))
  }

  @Test(arguments: [
    ("18:30", "18:00"),
    ("2 books", "Two books"),
    ("12,50", "1250"),
    ("-12", "12"),
    ("hello", "Hello in 2026"),
    ("2 and 2", "2"),
  ])
  func `changed added or missing numbers reject cleanup`(input: (String, String)) {
    #expect(!ReadyToSendValidation.preservesNumbers(original: input.0, edited: input.1))
  }
}
