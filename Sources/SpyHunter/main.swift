import AppKit

// Spy Hunter — a Swift/SpriteKit port of the 1983 Bally Midway arcade game.
// Developed by Tony Brice.

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
