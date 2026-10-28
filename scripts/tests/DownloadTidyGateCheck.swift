// Licensed under GPL-3.0. See LICENSE.
// swiftc Nook/Managers/DownloadManager/DownloadTidier.swift scripts/tests/DownloadTidyGateCheck.swift -o /tmp/dlgate && /tmp/dlgate

@main
struct DownloadTidyGateCheck {
    static func main() {
        // A name typed in the save panel is the person's.
        precondition(DownloadTidier.shouldTidy(isAutomaticFolder: false, isPrivate: false, origin: .network) == false)
        // Private windows and the Agent space.
        precondition(DownloadTidier.shouldTidy(isAutomaticFolder: true, isPrivate: true, origin: .network) == false)
        // Captures and Save PDF are named already.
        precondition(DownloadTidier.shouldTidy(isAutomaticFolder: true, isPrivate: false, origin: .capture) == false)
        precondition(DownloadTidier.shouldTidy(isAutomaticFolder: true, isPrivate: false, origin: .network) == true)

        func name(_ proposal: String, _ original: String) -> String? {
            DownloadTidier.acceptedName(proposal, replacing: original)
        }
        precondition(name("Navan Itinerary", "387494876.pdf") == "Navan Itinerary.pdf")
        // Version numbers and compound extensions survive; the model's own extension is dropped.
        precondition(name("Nook 1.3.0", "Nook-1.3.0.dmg") == "Nook 1.3.0.dmg")
        precondition(name("Nook 1.3.0.dmg", "a8f3c2e1.dmg") == "Nook 1.3.0.dmg")
        precondition(name("Backup May", "backup.tar.gz") == "Backup May.tar.gz")
        // Arc's guard: empty or dot-prefixed is refused, not repaired.
        precondition(name("", "1234567.pdf") == nil)
        precondition(name("   \n", "1234567.pdf") == nil)
        precondition(name(".hidden", "1234567.pdf") == nil)
        precondition(name("../../etc/passwd", "1234567.pdf") == nil)
        // One line, no separators, capped.
        precondition(name("Acme/Invoice\nsecond line", "1234567.pdf") == "Acme Invoice.pdf")
        let long = String(repeating: "word ", count: 40)
        precondition(name(long, "1234567.pdf")!.count <= DownloadTidier.maxLength + 4)
        // Nothing new, nothing letters.
        precondition(name("report", "report.pdf") == nil)
        precondition(name("1234", "987654.pdf") == nil)
        precondition(name("Report", "noextension") == "Report")
        // No trailing dot, and no extension the file never had.
        precondition(name("Report.", "a1b2c3d4.pdf") == "Report.pdf")
        precondition(name("setup.sh", "a1b2c3d4e5") == "setup")
        // Only machine-made names wait on the model.
        for messy in ["387494876.pdf", "a8f3c2e1b9d0.dmg", "IMG_4821.jpg", "download.pdf", "Report (1).pdf",
                      "3F2504E0-4F89-11D3-9A0C-0305E82C3301.zip", "untitled.txt"] {
            precondition(DownloadTidier.isMessy(messy), messy)
        }
        for tidy in ["Q3 Budget.xlsx", "Nook-1.3.0.dmg", "backup.tar.gz", "Swift Book.epub", "resume.pdf"] {
            precondition(!DownloadTidier.isMessy(tidy), tidy)
        }
        print("DownloadTidyGateCheck passed")
    }
}
