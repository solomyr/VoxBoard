# App Store listing — VoxBoard 0.4.0

## Name
VoxBoard

## Subtitle (30)
Private voice keyboard & AI

## Promotional text (170)
Speak, and VoxBoard types it — transcribed and polished entirely on your iPhone. Swipe typing, one-handed mode and Apple Watch dictation. No accounts, no cloud.

## Keywords (100)
dictation,voice typing,speech to text,keyboard,swipe,transcribe,offline,whisper,bulgarian,private

## Description
VoxBoard is a voice keyboard that keeps your words on your device.

Tap or hold the microphone on the keyboard, speak naturally, and VoxBoard transcribes what you said with a speech model running on your iPhone. An on-device AI writer can then fix punctuation and wording so the message is ready to send — names, numbers and your languages stay as you said them.

PRIVATE BY DESIGN
• Speech recognition and AI cleanup run entirely on your device
• No accounts, no analytics, no ads, no tracking
• Works offline once the models are downloaded
• Open source (GNU GPL v3): github.com/solomyr/VoxBoard

A FULL KEYBOARD, NOT JUST A MIC
• Dictate in any app: tap to start and stop, or hold to talk
• Swipe typing in 11 layouts, learning the words you use
• Smarter swipes from sentence context with Apple Intelligence, where available
• English, Bulgarian (phonetic and BDS), German, French, Spanish, Italian, Portuguese, Greek, Russian, Ukrainian and Turkish layouts
• One-handed mode, accents on long press, cursor control on the space bar, haptics

YOUR CHOICE OF MODELS
• Whisper (100 languages), Parakeet and Moonshine for speech
• Qwen, Gemma, Llama and SmolLM for text cleanup
• Pick the balance of speed and quality that suits your device

APPLE WATCH
Dictate on your wrist: VoxBoard on your iPhone transcribes and polishes, and you send the result in Messages or copy it to your iPhone.

COMPOSE
Record longer messages in the app, review and edit, then copy or share. VoxBoard never sends anything on its own.

Note: the first keyboard recording opens VoxBoard for a moment, because iOS does not let keyboards use the microphone. With Instant keyboard dictation on, later recordings happen right in the keyboard until the microphone times out; iOS shows its orange indicator while it is ready. You can turn this off at any time.

## What's new
First release.

## Category
Primary: Productivity · Secondary: Utilities

## URLs
Support: https://github.com/solomyr/VoxBoard/issues
Marketing: https://github.com/solomyr/VoxBoard
Privacy policy: https://github.com/solomyr/VoxBoard/blob/main/PRIVACY.md

## Copyright
2026 Petar Yankov

## Age rating
4+ (no objectionable content; free-form text input only)

## App Privacy
Data Not Collected.

## App Review notes
VoxBoard is a custom keyboard with on-device speech recognition.

How to test:
1. Open VoxBoard. On Compose, tap Download for the suggested speech model (Whisper Small) and text model (Qwen 3.5 0.8B). Downloads come from huggingface.co.
2. Settings › General › Keyboard › Keyboards › Add New Keyboard › VoxBoard, then enable Allow Full Access.
3. In any text field (for example Notes), switch to VoxBoard with the globe key and tap the microphone. The first time, VoxBoard opens briefly to start the microphone and returns automatically; speak, then tap the microphone again. The text is inserted.

Why Full Access: iOS keyboards cannot use the microphone, so the VoxBoard app records and transcribes, then passes the text to the keyboard through the app group shared container. Full Access is needed for that shared container and for haptics. No typed text is sent over the network.

Why the audio background mode: after a keyboard recording the app keeps its audio session active for a user-chosen time (15 minutes by default) so the next keyboard recording starts without switching apps. Nothing is captured until the user taps the microphone; iOS shows the microphone indicator while the session is ready. Users can end it from the keyboard (mic-off button) or in Settings, or turn the feature off entirely ("Instant keyboard dictation").

Apple Watch: the Watch app records and sends the audio to the iPhone app over WatchConnectivity; the iPhone transcribes and returns the text.

All processing is local; there is no account or login.
