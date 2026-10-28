// Licensed under GPL-3.0. See LICENSE.
// swiftc Nook/Managers/DownloadManager/DownloadTidyName.swift scripts/tests/DownloadTidyNameCheck.swift -o /tmp/tidy && /tmp/tidy

@main
struct DownloadTidyNameCheck {
    static func main() {
        // Worth renaming.
        for name in ["387494876.pdf", "IMG_20261028_101112.jpg", "download.pdf", "file (3).zip",
                     "a3f9c2e1b7d04e55.png", "Untitled.docx", "2026-10-28.csv"] {
            precondition(DownloadTidyName.looksMessy(name), "should be messy: \(name)")
        }
        // Already a name.
        for name in ["Navan Itinerary.pdf", "quarterly-plan.key", "Resume Abdul.pdf", "Nook 1.3.0.dmg"] {
            precondition(!DownloadTidyName.looksMessy(name), "should be clean: \(name)")
        }

        precondition(DownloadTidyName.cleaned("Navan Itinerary", replacing: "387494876.pdf") == "Navan Itinerary.pdf")
        // The model's own extension gives way to the file's real one.
        precondition(DownloadTidyName.cleaned("\"Navan Itinerary.txt\"", replacing: "387494876.pdf") == "Navan Itinerary.pdf")
        // No path tricks.
        precondition(DownloadTidyName.cleaned("../../etc/passwd", replacing: "1234567.txt") == "etc passwd.txt")
        // Only the first line, capped.
        let long = String(repeating: "word ", count: 40) + "\nsecond line"
        let capped = DownloadTidyName.cleaned(long, replacing: "123456.pdf")!
        precondition(capped.count <= DownloadTidyName.maxLength + 4 && !capped.contains("second"))
        // Nothing usable, or the same name back.
        precondition(DownloadTidyName.cleaned("1234", replacing: "987654.pdf") == nil)
        precondition(DownloadTidyName.cleaned("download", replacing: "download.pdf") == nil)
        precondition(DownloadTidyName.cleaned("Report", replacing: "noextension") == "Report")
        // Slugs and doubled extensions get tidied; typed names do not.
        precondition(DownloadTidyName.needsTidying("kovalam-tropical-wallpaper-bed.webp.jpeg"))
        precondition(DownloadTidyName.needsTidying("annual_report_final.pdf"))
        precondition(!DownloadTidyName.needsTidying("Navan Itinerary.pdf"))
        precondition(DownloadTidyName.ruleBased("kovalam-tropical-wallpaper-bed.webp.jpeg") == "kovalam tropical wallpaper bed.jpeg",
                     String(describing: DownloadTidyName.ruleBased("kovalam-tropical-wallpaper-bed.webp.jpeg")))
        precondition(DownloadTidyName.ruleBased("annual_report_final.pdf") == "annual report final.pdf")
        precondition(DownloadTidyName.ruleBased("IMG_20261028_101112.jpg") == nil, "IMG alone says nothing")
        precondition(DownloadTidyName.ruleBased("387494876.pdf") == nil)
        precondition(DownloadTidyName.ruleBased("NASA-mars-photo_a3f9c2e1b7.png") == "nasa mars photo.png",
                     String(describing: DownloadTidyName.ruleBased("NASA-mars-photo_a3f9c2e1b7.png")))
        print("DownloadTidyNameCheck passed")
    }
}
