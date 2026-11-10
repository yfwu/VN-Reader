// Appended only to the temporary source copy, never to the production app.
extension ReaderViewController {
    var auditCurrentController: SpreadPageController { pageVC.viewControllers!.first as! SpreadPageController }
    var auditPageController: UIPageViewController { pageVC }
    var auditIsTransitioning: Bool { isTransitioning }
    var auditCanScroll: Bool { pagerScrollView?.isScrollEnabled ?? false }
    func auditBeginTransition() -> UUID {
        let id = UUID()
        transitionID = id; isTransitioning = true
        pagerScrollView?.isScrollEnabled = false
        return id
    }
    func auditFinishTransition(_ id: UUID, page: Int, userInitiated: Bool = false) {
        finishTransition(id, focusedPage: page, userInitiated: userInitiated)
    }
    func auditSetVisiblePage(_ page: Int) {
        pageVC.setViewControllers([makeController(unitIndex(containing: page))!], direction: .forward, animated: false)
    }
}
