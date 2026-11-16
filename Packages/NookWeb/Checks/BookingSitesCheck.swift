// Licensed under GPL-3.0. See LICENSE.
//
//  BookingSitesCheck.swift
//  Nook
//
//  Which pages Look It Up treats as one venue's booking page, and the address it builds to
//  open that page on the person's party size and day.
//
//    L=Packages/NookWeb/Sources/NookWeb/Lookup
//    swiftc $L/LookupModels.swift $L/BookingSites.swift Packages/NookWeb/Checks/BookingSitesCheck.swift \
//           -o /tmp/booking-sites && /tmp/booking-sites
//

import Foundation

@main
struct BookingSitesCheck {
    static func main() {
        let venue = URL(string: "https://resy.com/cities/new-york-ny/venues/lilia")!
        let details = BookingDetails(people: 2, date: "2026-11-16", time: "19:00")
        precondition(BookingSites.isVenuePage(venue))
        precondition(BookingSites.isVenuePage(URL(string: "https://www.resy.com/cities/sf/venues/state-bird-provisions/")!))
        precondition(BookingSites.prefilled(venue, details)?.absoluteString == "https://resy.com/cities/new-york-ny/venues/lilia?seats=2&date=2026-11-16")
        precondition(BookingSites.prefilled(venue, BookingDetails(people: 4))?.query == "seats=4")
        precondition(BookingSites.prefilled(venue, BookingDetails(date: "2026-12-03"))?.query == "date=2026-12-03")
        precondition(BookingSites.prefilled(venue, BookingDetails()) == nil, "nothing to fill in")
        precondition(BookingSites.prefilled(venue, BookingDetails(time: "19:00")) == nil, "Resy takes no time in its address")

        // only a venue's own page on a known booking host
        for address in [
            "https://resy.com/cities/new-york-ny", "https://resy.com/", "https://resy.com/cities/new-york-ny/venues",
            "https://resy.com/cities/new-york-ny/venues/lilia/events/x", "https://blog.resy.com/cities/x/venues/y",
            "https://www.opentable.com/r/llama-inn", "https://evil.com/resy.com/cities/a/venues/b",
            "https://resy.com.evil.com/cities/a/venues/b", "http://resy.com/cities/a/venues/b", "https://notresy.com/cities/a/venues/b",
        ] {
            let url = URL(string: address)!
            precondition(!BookingSites.isVenuePage(url) && BookingSites.prefilled(url, details) == nil, address)
        }

        // what the address already carries is kept, and its own seats or date are replaced
        precondition(BookingSites.prefilled(URL(string: "https://resy.com/cities/a/venues/b?date=2020-01-01&x=1&seats=9")!, details)?.query == "x=1&seats=2&date=2026-11-16")
        // a date in another form, or a party no table seats, is left out
        precondition(BookingSites.prefilled(venue, BookingDetails(people: 2, date: "11/16/2026"))?.query == "seats=2")
        precondition(BookingSites.prefilled(venue, BookingDetails(people: 2, date: "2026-13-45"))?.query == "seats=2")
        precondition(BookingSites.prefilled(venue, BookingDetails(people: 0, date: "2026-11-16"))?.query == "date=2026-11-16")
        precondition(BookingSites.prefilled(venue, BookingDetails(people: 500, date: "2026-11-16"))?.query == "date=2026-11-16")
        precondition(BookingSites.prefilled(venue, BookingDetails(people: -3)) == nil)

        // a venue page is a place's card only when the person named that place, and the search was for it
        func page(_ slug: String) -> URL { URL(string: "https://resy.com/cities/new-york-ny/venues/\(slug)")! }
        let asked = "table for 2 tomorrow at 7pm at lilia or kings co imperial in brooklyn"
        precondition(BookingSites.isPlace(page("kings-co-imperial"), request: asked, search: "kings co imperial brooklyn table"))
        precondition(BookingSites.isPlace(page("kings-co-imperial-lower-east-side"), request: asked, search: "Kings Co Imperial brooklyn"))
        precondition(BookingSites.isPlace(venue, request: asked, search: "lilia brooklyn table"))
        precondition(BookingSites.isPlace(page("joes-pizza"), request: "a table at Joe\u{2019}s Pizza tonight", search: "joe's pizza brooklyn"))
        // another venue the search brought back, whatever words its address shares with the request
        let wide = "book the best table at lilia or kings co imperial in brooklyn new york"
        for slug in ["misi", "julianas", "kings-highway-diner", "brooklyn-table", "the-table", "new-york-grill", "table", "-"] {
            precondition(!BookingSites.isPlace(page(slug), request: wide, search: "the best kings co imperial brooklyn table new york"), slug)
        }
        precondition(!BookingSites.isPlace(venue, request: asked, search: "kings co imperial brooklyn table"), "the right place under another place's search")
        precondition(!BookingSites.isPlace(URL(string: "https://www.kingscoimperial.com/")!, request: asked, search: "kings co imperial"), "not a venue page at all")
        precondition(!BookingSites.isPlace(venue, request: "", search: "lilia") && !BookingSites.isPlace(venue, request: asked, search: ""))
        // the second search is for what a site in the table books, and nothing else
        precondition(BookingSites.searchWords(for: "table for 2 at lilia tomorrow") == ["resy"])
        precondition(BookingSites.searchWords(for: "Dinner reservation at Lilia") == ["resy"])
        precondition(BookingSites.searchWords(for: "buy 2 tickets for the lion king next saturday").isEmpty)
        precondition(BookingSites.searchWords(for: "book a hotel room in austin for friday").isEmpty)

        // what a model is given to turn "tomorrow" or "friday" into a date: no arithmetic left to it
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 21))!
        let days = BookingCalendar.text(from: sunday, calendar: calendar)
        precondition(days.contains("Today is Sunday 2026-11-15") && days.contains("Tomorrow is Monday 2026-11-16"))
        precondition(days.contains("Friday 2026-11-20") && days.contains("Saturday 2026-11-21") && days.contains("Saturday 2026-11-28"))
        precondition(!days.contains("2026-11-30"), "two weeks, no more")

        // a day the request names in words is settled in code: the model put "next saturday" on a Tuesday
        func day(_ request: String, _ modelSaid: String?) -> String? {
            BookingCalendar.corrected(BookingDetails(people: 2, date: modelSaid), request: request, today: sunday, calendar: calendar).date
        }
        precondition(day("buy 2 tickets for the lion king next saturday", "2026-11-24") == "2026-11-21")
        precondition(day("table tomorrow at 7", "2026-11-18") == "2026-11-16")
        precondition(day("a table Tonight", nil) == "2026-11-15" && day("lunch today", "2026-11-17") == "2026-11-15")
        precondition(day("dinner on Friday", "2026-11-20") == "2026-11-20")
        precondition(day("brunch on sunday", "2026-11-15") == "2026-11-22", "a named weekday is the next one after today")
        precondition(day("dinner on december 3", "2026-12-03") == "2026-12-03", "no day word: the model's date stands")
        precondition(day("a table for 2", nil) == nil)
        // a date the person gave in figures or by month is theirs; a day word beside it changes nothing
        precondition(day("table for 2 on saturday december 5 at 7pm at lilia", "2026-12-05") == "2026-12-05")
        precondition(day("dinner friday the 27th", "2026-11-27") == "2026-11-27")
        precondition(day("table for 4 at sunday in brooklyn on december 3", "2026-12-03") == "2026-12-03")
        precondition(day("dinner on 11/27, a friday", "2026-11-27") == "2026-11-27")
        // counted from a day word: the model's reading stands
        precondition(day("the saturday after next", "2026-11-28") == "2026-11-28")
        precondition(day("a week from tomorrow", "2026-11-23") == "2026-11-23")
        precondition(day("the day after tomorrow", "2026-11-17") == "2026-11-17")
        precondition(day("friday in two weeks", "2026-12-04") == "2026-12-04")
        // the model's date stands when it is the weekday named and still ahead
        precondition(day("dinner next friday", "2026-11-27") == "2026-11-27")
        // a weekday the model read no date from names no day: it may be part of a place's name
        precondition(day("a table at sunday in brooklyn", nil) == nil && day("the saturday night live cast", nil) == nil)
        precondition(BookingCalendar.corrected(BookingDetails(people: 4, date: "2026-11-18", time: "20:00"), request: "tomorrow", today: sunday, calendar: calendar)
                     == BookingDetails(people: 4, date: "2026-11-16", time: "20:00"), "only the day changes")

        // what a model answers is taken only when it is well formed
        precondition(BookingDetails.cleaned(people: 2, date: "2026-11-16", time: "19:00") == BookingDetails(people: 2, date: "2026-11-16", time: "19:00"))
        precondition(BookingDetails.cleaned(people: 0, date: "", time: "") == BookingDetails())
        precondition(BookingDetails.cleaned(people: 2, date: "tomorrow", time: "7pm") == BookingDetails(people: 2))
        precondition(BookingDetails.cleaned(people: 99, date: "2026-02-30", time: "25:00") == BookingDetails())
        precondition(BookingDetails.cleaned(people: 6, date: " 2026-12-03 ", time: "7:05") == BookingDetails(people: 6, date: "2026-12-03", time: "07:05"))
        precondition(BookingDetails(people: 2).hasDetails && BookingDetails(date: "2026-12-03").hasDetails && !BookingDetails(time: "19:00").hasDetails)
    }
}
