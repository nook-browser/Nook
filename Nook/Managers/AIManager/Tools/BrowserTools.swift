//
//  BrowserTools.swift
//  Nook
//
//  Tool definitions for AI-browser interaction
//

import Foundation

enum BrowserTools {
    static let navigateToURL = AIToolDefinition(
        name: "navigateToURL",
        description: "Navigate the current tab to a URL, or open a new tab with the URL",
        parameters: [
            "type": "object",
            "properties": [
                "url": ["type": "string", "description": "The URL to navigate to"],
                "newTab": ["type": "boolean", "description": "Whether to open in a new tab (default: false)"]
            ],
            "required": ["url"]
        ]
    )

    static let readPageContent = AIToolDefinition(
        name: "readPageContent",
        description: "Read the text content of the current page, including title, URL, and body text",
        parameters: [
            "type": "object",
            "properties": [
                "maxLength": ["type": "integer", "description": "Maximum character length to return (default: 8000)"],
                "selector": ["type": "string", "description": "Optional CSS selector to read content from a specific element"]
            ]
        ]
    )

    static let clickElement = AIToolDefinition(
        name: "clickElement",
        description: "Click an element on the page. Provide EITHER a CSS selector OR the visible text of the element to click. When using text, it finds buttons, links, and inputs whose visible text contains your query.",
        parameters: [
            "type": "object",
            "properties": [
                "selector": ["type": "string", "description": "CSS selector for the element to click"],
                "text": ["type": "string", "description": "Visible text of the element to click (searches buttons, links, inputs, [role=button])"]
            ]
        ]
    )

    static let getInteractiveElements = AIToolDefinition(
        name: "getInteractiveElements",
        description: "Get all interactive elements on the page (buttons, links, inputs, selects) with their text, type, selector, and attributes. Essential before clicking — use this to see what you can interact with.",
        parameters: [
            "type": "object",
            "properties": [
                "filter": ["type": "string", "description": "Optional text filter to narrow results (case-insensitive match on text/aria-label/placeholder)"],
                "limit": ["type": "integer", "description": "Maximum number of elements to return (default: 50)"]
            ]
        ]
    )

    static let extractStructuredData = AIToolDefinition(
        name: "extractStructuredData",
        description: "Extract structured data from the page (schema.org, Open Graph, meta tags, or custom selectors)",
        parameters: [
            "type": "object",
            "properties": [
                "type": [
                    "type": "string",
                    "enum": ["schema_org", "open_graph", "meta", "custom"],
                    "description": "Type of data to extract"
                ],
                "selectors": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "CSS selectors for custom extraction"
                ]
            ],
            "required": ["type"]
        ]
    )

    static let summarizePage = AIToolDefinition(
        name: "summarizePage",
        description: "Get the full text content of the page for summarization",
        parameters: [
            "type": "object",
            "properties": [:] as [String: Any]
        ]
    )

    static let searchInPage = AIToolDefinition(
        name: "searchInPage",
        description: "Search for text on the current page and return matches with surrounding context",
        parameters: [
            "type": "object",
            "properties": [
                "query": ["type": "string", "description": "Text to search for on the page"]
            ],
            "required": ["query"]
        ]
    )

    static let getTabList = AIToolDefinition(
        name: "getTabList",
        description: "Get a list of all open tabs with their titles and URLs",
        parameters: [
            "type": "object",
            "properties": [:] as [String: Any]
        ]
    )

    static let switchTab = AIToolDefinition(
        name: "switchTab",
        description: "Switch to a tab by its index (0-based) from the tab list",
        parameters: [
            "type": "object",
            "properties": [
                "index": ["type": "integer", "description": "Index of the tab to switch to"]
            ],
            "required": ["index"]
        ]
    )

    static let createTab = AIToolDefinition(
        name: "createTab",
        description: "Create a new tab, optionally with a URL",
        parameters: [
            "type": "object",
            "properties": [
                "url": ["type": "string", "description": "Optional URL to load in the new tab"]
            ]
        ]
    )

    static let getSelectedText = AIToolDefinition(
        name: "getSelectedText",
        description: "Get the currently selected text on the page",
        parameters: [
            "type": "object",
            "properties": [:] as [String: Any]
        ]
    )

    static let executeJavaScript = AIToolDefinition(
        name: "executeJavaScript",
        description: "Execute arbitrary JavaScript on the current page. Use with caution.",
        parameters: [
            "type": "object",
            "properties": [
                "code": ["type": "string", "description": "JavaScript code to execute"]
            ],
            "required": ["code"]
        ]
    )

    static let allTools: [AIToolDefinition] = [
        navigateToURL, readPageContent, clickElement,
        getInteractiveElements,
        extractStructuredData, summarizePage, searchInPage,
        getTabList, switchTab, createTab, getSelectedText,
        executeJavaScript
    ]

    static let toolsByName: [String: AIToolDefinition] = {
        Dictionary(uniqueKeysWithValues: allTools.map { ($0.name, $0) })
    }()
}
