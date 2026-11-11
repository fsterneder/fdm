/// Stable stored values: existing quarter/eighth/triplet/sixteenth settings stay 1...4.
public enum Subdivision {
    public static let options = [-2, -1, 1, 2, 3, 4]
    public static func restored(_ value: Int) -> Int { options.contains(value) ? value : 1 }
    public static func label(_ value: Int) -> String {
        switch value {
        case -2: return "1/1"
        case -1: return "1/2"
        case 2: return "1/8"
        case 3: return "1/8T"
        case 4: return "1/16"
        default: return "1/4"
        }
    }
    public static func description(_ value: Int) -> String {
        switch value {
        case -2: return "One click every four beats"
        case -1: return "One click every two beats"
        default: return "\(max(1, value)) clicks per beat"
        }
    }
}
