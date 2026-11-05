import CoreFoundation

// Private CoreGraphics calls that let a background app set the mouse cursor. Without them,
// macOS ignores cursor changes from apps that aren't frontmost, and this one never is.
@_silgen_name("_CGSDefaultConnection")
private func _CGSDefaultConnection() -> Int32

@_silgen_name("CGSSetConnectionProperty")
@discardableResult
private func CGSSetConnectionProperty(_ connection: Int32, _ target: Int32, _ key: CFString, _ value: CFTypeRef) -> Int32

enum BackgroundCursor {
    static func allowSettingCursorWhileInBackground() {
        let connection = _CGSDefaultConnection()
        CGSSetConnectionProperty(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    }
}
