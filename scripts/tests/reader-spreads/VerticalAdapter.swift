// Appended only to the temporary source copy, never to the production app.
final class AuditScrollView: UIScrollView {
    var auditDragging = false, auditDecelerating = false
    override var isDragging: Bool { auditDragging }
    override var isDecelerating: Bool { auditDecelerating }
}
final class AuditPan: UIPanGestureRecognizer {
    var simulatedState: UIGestureRecognizer.State = .possible
    override var state: UIGestureRecognizer.State {
        get { simulatedState }
        set { simulatedState = newValue }
    }
}
extension VerticalReaderController {
    var auditTable: UITableView { table }
    func auditAspect(_ page: Int, size: CGSize) { updateAspect(page, size) }
    func auditPan(_ gesture: UIPanGestureRecognizer) { userPanChanged(gesture) }
    func auditMoveViewport(to page: Int, from scrollView: UIScrollView? = nil) {
        // Set the viewport deterministically, then dispatch the real delegate
        // callback with either passive or recognizer-derived input state.
        let offset = CGPoint(x: 0, y: table.rectForRow(at: IndexPath(row: page, section: 0)).minY)
        table.delegate = nil
        table.setContentOffset(offset, animated: false)
        table.delegate = self
        scrollViewDidScroll(scrollView ?? table)
    }
    func auditPassiveMove(to page: Int, from scrollView: UIScrollView) {
        withPassiveScrolling { auditMoveViewport(to: page, from: scrollView) }
    }
}
