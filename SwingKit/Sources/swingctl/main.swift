// swingctl — runs the SwingKit measurement pipeline on video files from the Mac CLI.
// This is the accuracy-validation loop: same code as the app, real sample swings in,
// hard numbers + annotated frames out.
import Foundation
import SwingKit

let args = CommandLine.arguments
print("swingctl — SwingKit \(Joint.allCases.count)-joint pipeline. Analysis lands in Phase 2.")
