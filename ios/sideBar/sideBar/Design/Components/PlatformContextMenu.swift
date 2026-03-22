import SwiftUI

#if os(iOS)
import UIKit

func shouldUseUIKitContextMenu(on idiom: UIUserInterfaceIdiom) -> Bool {
    false
}
#endif

extension View {
    @ViewBuilder
    func platformContextMenu(items: [SidebarMenuItem]) -> some View {
        #if os(iOS)
        self.contextMenu {
            sidebarMenuItemsView(items)
        }
        #else
        self.contextMenu {
            sidebarMenuItemsView(items)
        }
        #endif
    }
}
