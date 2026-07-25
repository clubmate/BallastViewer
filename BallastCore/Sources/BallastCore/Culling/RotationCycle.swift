/// The EXIF orientation cycle applied by the Rotate action (spec §6.6):
/// 1 (normal) → 6 (90° CW) → 3 (180°) → 8 (90° CCW) → 1 …
/// Mirrored orientations (2/4/5/7) read from files are honoured for display
/// but jump to 6 on the first rotation.
public enum RotationCycle {
    public static func next(after orientation: Int) -> Int {
        switch orientation {
        case 1: 6
        case 6: 3
        case 3: 8
        case 8: 1
        default: 6
        }
    }
}
