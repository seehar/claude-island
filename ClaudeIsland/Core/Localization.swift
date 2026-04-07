//
//  Localization.swift
//  ClaudeIsland
//
//  String localization helper extension
//

import Foundation

extension String {
    /// Returns a localized version of this string using the default table (Localizable.strings).
    var localized: String {
        NSLocalizedString(self, comment: "")
    }
}
