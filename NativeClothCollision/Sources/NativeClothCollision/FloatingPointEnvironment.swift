import CNativeClothCollision

/// Read-only platform bridge. It never changes the caller's rounding mode.
public enum FloatingPointEnvironment {
    public static var isNearestRounding:Bool {
        ncc_floating_point_rounding_is_nearest() == 1
    }
}
