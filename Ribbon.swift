//
//  Ribbon.swift
//  Overlay
//
//  Created by Tom Witjes on 18.11.26.
//


import ApplicationServices

struct ExcelRibbon {
    var tabs: [RibbonTab]
}

struct RibbonTab: Identifiable {
    let id: String
    let title: String
    let element: AXUIElement
    var groups: [RibbonGroup]
}

struct RibbonGroup: Identifiable {
    let id: String
    let title: String?
    let frame: CGRect
    var commands: [RibbonCommand]
}

struct RibbonCommand: Identifiable {
    let id: String
    let title: String
    let role: String
    let identifier: String?
    let element: AXUIElement
    let frame: CGRect
    let actions: [String]

    var supportsPress: Bool {
        actions.contains("AXPress")
    }
}
