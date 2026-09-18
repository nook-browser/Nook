// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  PageSession+Blockable.swift
//  Nook
//
//  PageSession satisfies NookBlocker's page seam as-is: itemID, isOAuthFlow and
//  webView are already its own stored properties. Task 6 moves this into NookWeb.
//

import NookBlocker

extension PageSession: BlockablePage {}
