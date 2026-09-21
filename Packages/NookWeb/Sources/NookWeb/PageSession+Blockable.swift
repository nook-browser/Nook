// Licensed under GPL-3.0. See LICENSE.
//
//  PageSession+Blockable.swift
//  Nook
//
//  PageSession satisfies NookBlocker's page seam as-is: itemID, isOAuthFlow and
//  webView are already its own stored properties. Task 6 moves this into NookWeb.
//

import NookBlocker

extension PageSession: BlockablePage {}
