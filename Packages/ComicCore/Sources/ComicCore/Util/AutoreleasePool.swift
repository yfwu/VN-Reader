import Foundation

/// Drains Objective-C temporaries when `body` returns (a no-op on Linux). Long
/// loops need this: anything Foundation autoreleases otherwise lives until the
/// enclosing work item ends, which for a big book is gigabytes later.
@inline(__always)
func withAutoreleasePool<T>(_ body: () throws -> T) rethrows -> T {
    #if canImport(ObjectiveC)
    return try autoreleasepool(invoking: body)
    #else
    return try body()
    #endif
}
