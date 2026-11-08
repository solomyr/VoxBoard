import SwiftUI

struct SessionInfoView: View {
  var body: some View {
    List {
      Section("Tap or hold to record") {
        Text("Tap the keyboard microphone to start, and tap again to finish. Or hold it while you speak and let go to finish. Your words are transcribed, polished if the AI writer is on, and inserted where you are typing, all on this device.")
      }
      Section("Why VoxBoard opens once") {
        Text("iOS does not let keyboards use the microphone. The VoxBoard app records for the keyboard instead, so the first recording opens VoxBoard for a moment to turn the microphone on, then returns you to the app where you were typing.")
        Text("With Instant keyboard dictation on, VoxBoard keeps the microphone ready afterwards, so later recordings happen right in the keyboard with no app switch. Nothing is captured until you tap the mic. After the idle time you choose in Settings, the microphone turns off and the next recording opens VoxBoard again.")
      }
      Section("The orange indicator") {
        Text("iOS shows the orange microphone indicator the whole time VoxBoard is ready, not only while you speak. Keeping it ready also uses some battery. You can turn it off from the keyboard or in Settings at any time. A phone call or other audio interruption turns it off and it does not restart by itself.")
      }
      Section("Your audio") {
        Text("While you dictate, VoxBoard saves audio and transcribes it on this device. Review or delete recordings in History and choose how long they are kept in Settings. No audio or text is uploaded for processing.")
      }
    }
    .navigationTitle("Microphone access")
    .navigationBarTitleDisplayMode(.inline)
  }
}
