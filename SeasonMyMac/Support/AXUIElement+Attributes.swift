import ApplicationServices
import CoreGraphics

/// Small conveniences for reading Accessibility attributes.
extension AXUIElement {
    func attribute(_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success else { return nil }
        return value
    }

    var frame: CGRect? {
        guard
            let position = axValue(attribute(kAXPositionAttribute), as: CGPoint.self, type: .cgPoint),
            let size = axValue(attribute(kAXSizeAttribute), as: CGSize.self, type: .cgSize)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    private func axValue<T>(_ value: CFTypeRef?, as _: T.Type, type: AXValueType) -> T? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        // The type ID check above guarantees this is an AXValue.
        guard AXValueGetValue(value as! AXValue, type, pointer) else { return nil }
        return pointer.pointee
    }
}
