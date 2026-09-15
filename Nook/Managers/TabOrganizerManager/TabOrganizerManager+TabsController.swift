//
//  TabOrganizerManager+TabsController.swift
//  Nook
//
//  Tab organizer entry point against the new tab model. Track T5 moves the organizer onto
//  TabsController here (its undo becomes `tabs.apply(change)`); until then it changes nothing.
//

import Foundation

extension TabOrganizerManager {
    func organizeTabs(in spaceID: UUID, using tabs: TabsController) async {}
}
