import Testing
@testable import OpenShelf

struct ExtractTransformsTests {
    typealias E = ExtractTransforms

    @Test func links() {
        let text = "See https://a.com/x?q=1 and www.b.org, mail me@c.io, again https://a.com/x?q=1."
        #expect(E.extract(.links, from: text) == "https://a.com/x?q=1\nwww.b.org")
    }

    @Test func emails() {
        #expect(E.extract(.emails, from: "To: Ann <ann.lee+news@mail.example.com>, bob@x.io; ann.lee+news@mail.example.com") == "ann.lee+news@mail.example.com\nbob@x.io")
    }

    @Test func numbers() {
        #expect(E.extract(.numbers, from: "Paid 1,234.50 then -7 and 3.14; v2 and abc123 aren't; 42.") == "1,234.50\n-7\n3.14\n42")
        // Not parts of an IP, a version, a date, a time or "x-5"; repeats are kept.
        #expect(E.extract(.numbers, from: "ip 192.168.1.1 v1.2.3 on 2024-03-15 at 10:30, x-5, 5, 5") == "5\n5")
    }

    @Test func phoneNumbers() {
        let found = E.matches(.phoneNumbers, in: "Call (555) 123-4567 or +1 415 555 0100 today")
        #expect(found.count == 2)
        #expect(found.first?.contains("123-4567") == true)
    }

    @Test func dates() {
        // Fixed dates only: the system's detector reads relative ones ("next Tuesday") and
        // even "Due <yesterday>" against the real clock.
        let found = E.matches(.dates, in: "Met on 2025-01-05, then on January 5, 2024. Nothing else.")
        #expect(found == ["2025-01-05", "January 5, 2024"])
    }

    /// Nothing of that kind: the text stays as it is ("Nothing to change").
    @Test(arguments: E.Kind.allCases)
    func nothingFoundLeavesTheText(kind: E.Kind) {
        #expect(E.extract(kind, from: "just words here") == "just words here")
        #expect(E.extract(kind, from: "") == "")
    }
}
