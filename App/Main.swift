// Licensed under GPL-3.0. See LICENSE.
//
//  Main.swift
//  Nook
//
//  The process entry. The bundle-id migration must finish before NookApp's stored properties are
//  built, since those already read UserDefaults and Application Support.
//

@main
enum Main {
    static func main() {
        LegacyDataMigration.migrateIfNeeded()
        NookApp.main()
    }
}
