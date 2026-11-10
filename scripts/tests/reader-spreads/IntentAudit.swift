import UIKit
import ComicCore

extension AuditApp {
    @MainActor func runIntentChecks(scene: UIWindowScene) async throws {
        let model = ReaderViewModel()
        let reader = ReaderViewController(model: model)
        window?.rootViewController = reader
        reader.loadViewIfNeeded()
        window?.addSubview(reader.view)
        reader.view.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        reader.viewDidLayoutSubviews()
        try check(!model.pageEvents.isEmpty && model.userPageEvents.isEmpty, "initial pager rendering never reports user navigation")

        model.currentPage = 3 // Mirrors the model adopting merged progress before asking its pager.
        reader.go(toPage: 3, animated: false, userInitiated: false)
        model.widePages = [3]
        reader.widePagesChanged()
        reader.reloadForSettings()
        reader.view.frame.size = CGSize(width: 600, height: 900)
        reader.viewDidLayoutSubviews()
        try check(model.currentPage == 3 && model.visiblePages == [3] && model.userPageEvents.isEmpty,
                  "remote restore, wide discovery, settings and resize stay passive")

        reader.go(toPage: 3, animated: false, userInitiated: true)
        try check(model.userPageEvents == [3], "explicit same-page jump remains a user navigation")
        model.pageEvents = []
        model.settings.animatePageTurns = false
        reader.perform(.next)
        reader.perform(.previous)
        try check(model.userPageEvents == [4, 3], "next and previous each report one user navigation")

        model.pageEvents = []
        model.settings.animatePageTurns = true
        reader.go(toPage: 4, animated: true, userInitiated: true)
        for _ in 0..<30 where reader.auditIsTransitioning { await settle() }
        try check(!reader.auditIsTransitioning && model.userPageEvents == [4], "animated user navigation reports once, completion stays passive")

        model.pageEvents = []
        reader.pageViewController(reader.auditPageController, willTransitionTo: [])
        reader.pageViewController(reader.auditPageController, didFinishAnimating: true,
                                  previousViewControllers: [], transitionCompleted: false)
        await settle()
        try check(model.currentPage == 4 && model.userPageEvents.isEmpty, "cancelled swipe does not report user navigation")

        reader.pageViewController(reader.auditPageController, willTransitionTo: [])
        reader.auditSetVisiblePage(3)
        reader.pageViewController(reader.auditPageController, didFinishAnimating: true,
                                  previousViewControllers: [], transitionCompleted: true)
        await settle()
        try check(model.userPageEvents == [3], "committed swipe reports exactly one user navigation")

        model.pageEvents = []
        let queued = reader.auditBeginTransition()
        reader.go(toPage: 4, animated: false, userInitiated: true)
        reader.go(toPage: 0, animated: false, userInitiated: false)
        reader.auditFinishTransition(queued, page: 3)
        await settle()
        try check(model.currentPage == 4 && model.userPageEvents == [4], "queued user jump cannot be replaced by passive restore")

        model.pageEvents = []
        let committed = reader.auditBeginTransition()
        model.currentPage = 0
        reader.go(toPage: 0, animated: false, userInitiated: false)
        reader.auditFinishTransition(committed, page: 3, userInitiated: true)
        await settle()
        try check(model.currentPage == 3 && model.userPageEvents == [3], "committed swipe wins over queued remote restore")

        model.pageEvents = []
        let cancelled = reader.auditBeginTransition()
        model.currentPage = 0
        reader.go(toPage: 0, animated: false, userInitiated: false)
        reader.auditFinishTransition(cancelled, page: 3)
        await settle()
        try check(model.visiblePages == [0, 1] && model.userPageEvents.isEmpty, "cancelled transition can apply queued restore without a write")

        model.pageEvents = []
        let obsolete = reader.auditBeginTransition()
        model.pager = nil
        reader.auditFinishTransition(obsolete, page: 3, userInitiated: true)
        await settle()
        try check(model.pageEvents.isEmpty, "detached pager completion cannot report user navigation")

        let verticalModel = ReaderViewModel()
        verticalModel.layout = .vertical
        verticalModel.currentPage = 2
        let vertical = VerticalReaderController(model: verticalModel)
        window?.rootViewController = vertical
        vertical.loadViewIfNeeded()
        window?.addSubview(vertical.view)
        vertical.view.frame = CGRect(x: 0, y: 0, width: 400, height: 600)
        vertical.viewWillLayoutSubviews(); vertical.viewDidLayoutSubviews()
        try check(verticalModel.visiblePages == [2] && verticalModel.userPageEvents.isEmpty, "initial vertical positioning stays passive")

        verticalModel.currentPage = 3
        vertical.go(toPage: 3, animated: false, userInitiated: false)
        vertical.reloadForSettings()
        vertical.view.frame.size = CGSize(width: 450, height: 650)
        vertical.viewWillLayoutSubviews(); vertical.viewDidLayoutSubviews()
        vertical.auditAspect(0, size: CGSize(width: 100, height: 240))
        await settle()
        try check(verticalModel.userPageEvents.isEmpty, "vertical remote restore, settings, resize and decoded row changes stay passive")

        verticalModel.pageEvents = []
        vertical.go(toPage: 3, animated: false, userInitiated: true)
        try check(verticalModel.userPageEvents == [3], "explicit vertical same-page jump reports user intent once")

        verticalModel.pageEvents = []
        let drag = AuditScrollView()
        drag.auditDragging = true
        vertical.scrollViewWillBeginDragging(drag)
        vertical.auditMoveViewport(to: 2, from: drag)
        vertical.scrollViewDidEndDragging(drag, willDecelerate: true)
        drag.auditDragging = false; drag.auditDecelerating = true
        vertical.auditMoveViewport(to: 1, from: drag)
        vertical.scrollViewDidEndDecelerating(drag)
        try check(verticalModel.userPageEvents == [2, 1], "vertical drag and deceleration report actual reading changes")

        verticalModel.pageEvents = []
        vertical.scrollViewWillBeginDragging(drag)
        vertical.scrollViewDidScroll(drag)
        verticalModel.pageEvents = []
        vertical.auditPassiveMove(to: 0, from: drag)
        vertical.auditAspect(0, size: CGSize(width: 100, height: 300))
        try check(verticalModel.userPageEvents.isEmpty, "passive row corrections do not inherit an active drag intent")

        vertical.auditMoveViewport(to: 0, from: drag)
        vertical.scrollViewDidEndDecelerating(drag)
        try check(verticalModel.userPageEvents == [0] && verticalModel.currentPage == 0,
                  "real scroll ending on a passively reported row still persists that row")

        verticalModel.pageEvents = []
        verticalModel.currentPage = 3
        vertical.go(toPage: 3, animated: false, userInitiated: false)
        vertical.scrollViewDidEndDecelerating(drag)
        try check(verticalModel.userPageEvents.isEmpty, "remote positioning cancels old deceleration intent")

        verticalModel.pageEvents = []
        let pan = AuditPan()
        pan.simulatedState = .began
        vertical.auditPan(pan)
        pan.simulatedState = .ended
        vertical.auditPan(pan)
        try check(verticalModel.userPageEvents == [3], "existing pan recognizer reports indirect scroll intent without dragging flags")

        verticalModel.pageEvents = []
        verticalModel.pager = nil
        vertical.go(toPage: 2, animated: false, userInitiated: true)
        try check(verticalModel.pageEvents.isEmpty, "detached vertical reader cannot report navigation")
    }
}
