import SwiftUI

extension WebsitesDetailView {
    func closeWebsite() {
        let closePlan = makeWorkspaceItemClosePlan()
        applyWorkspaceItemClosePlan(closePlan)
        viewModel.clearSelection()
    }
}
