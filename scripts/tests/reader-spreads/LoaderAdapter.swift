// Appended only to the temporary source copy, never to the production app.
extension PageImageLoader {
    func auditSeedSharedTask(_ task: Task<UIImage, Error>, page: Int) { inFlight[page] = task }
    func auditSeedCache(_ image: UIImage, page: Int) { cache.setObject(image, forKey: NSNumber(value: page)) }
}
