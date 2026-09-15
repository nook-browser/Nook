//
//  ExtensionManager+PageSessionHooks.swift
//  Nook
//
//  Extension notifications TabsController and PageSession call. Owned by foundation until
//  track T4 implements them against ExtensionTabAdapter keyed by item id.
//  `wakeBackgroundWorkers()` already lives in ExtensionManager+TabNotifications.swift.
//

import Foundation
import WebKit

extension ExtensionManager {
    func notifyTabOpened(_ session: PageSession) {}

    func notifyTabActivated(new: PageSession, previous: PageSession?) {}

    func notifyTabClosed(itemID: UUID) {}

    func notifyTabPropertiesChanged(_ session: PageSession, properties: WKWebExtension.TabChangedProperties) {}
}
