import Foundation
import Testing
@testable import OpenShelf

struct CodeTransformsTests {
    typealias C = CodeTransforms

    @Test(arguments: [
        (C.Format.url, "a b&c=d/é", "a%20b%26c%3Dd%2F%C3%A9"),
        (.base64, "hello é", "aGVsbG8gw6k="),
        (.html, "<a href=\"x\">Tom & 'Jerry'</a>", "&lt;a href=&quot;x&quot;&gt;Tom &amp; &#39;Jerry&#39;&lt;/a&gt;"),
        (.jsonString, "say \"hi\"\n\ttab /path", "\"say \\\"hi\\\"\\n\\ttab /path\""),
        (.hex, "Hi é", "486920c3a9"),
        (.unicode, "café 😀", "caf\\u00e9 \\ud83d\\ude00"),
    ])
    func encodesAndDecodesBack(format: C.Format, plain: String, encoded: String) {
        #expect(C.encode(plain, as: format) == encoded)
        #expect(C.decode(encoded, from: format) == plain)
    }

    @Test func decodersAreForgiving() {
        // URL-safe Base64 without padding, with a line break.
        #expect(C.decode("aGVsbG8gw6k\n", from: .base64) == "hello é")
        #expect(C.decode("_-8", from: .base64) == "_-8")
        #expect(C.decode("Pz8_", from: .base64) == "???")
        // Hex with spaces, colons or 0x.
        #expect(C.decode("48 69:21", from: .hex) == "Hi!")
        #expect(C.decode("0x4869", from: .hex) == "Hi")
        // A JSON string's content without its quotes.
        #expect(C.decode("line\\nnext", from: .jsonString) == "line\nnext")
        // \u{…} and \U escapes.
        #expect(C.decode("\\u{1F600} \\U0001F600", from: .unicode) == "😀 😀")
        // Numeric and named HTML entities.
        #expect(C.decode("&#233;&amp;&lt;", from: .html) == "é&<")
        // A lone half of a surrogate pair stays as written.
        #expect(C.decode("\\ud83d alone", from: .unicode) == "\\ud83d alone")
    }

    /// Text a decoder can't read comes back unchanged ("Nothing to change").
    @Test(arguments: [(C.Format.base64, "not base64!"), (.hex, "xyz"), (.hex, "abc"), (.jsonString, "\"unterminated"), (.url, "100%")])
    func unreadableTextIsUnchanged(format: C.Format, text: String) {
        #expect(C.decode(text, from: format) == text)
    }

    @Test func jwtHeaderAndPayload() {
        let header = Data(#"{"alg":"HS256","typ":"JWT"}"#.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        let payload = Data(#"{"sub":"42","name":"Ann/B"}"#.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        let read = C.readJWT("\(header).\(payload).signature")
        #expect(read == "{\n  \"alg\" : \"HS256\",\n  \"typ\" : \"JWT\"\n}\n\n{\n  \"name\" : \"Ann/B\",\n  \"sub\" : \"42\"\n}")
        #expect(C.readJWT("not.a.jwt") == nil)
        // Two parts that decode are still not a JWT.
        #expect(C.readJWT("\(header).\(payload)") == nil)
        #expect(C.readJWT("plain text") == nil)
        // As copied from a request header.
        #expect(C.readJWT("Bearer \(header).\(payload).sig") == read)
        #expect(C.readJWT("\"\(header).\(payload).sig\"") == read)
        // Five parts is an encrypted JWE, not readable here.
        #expect(C.readJWT("\(header).\(payload).c.d.e") == nil)
    }

    @Test func generators() throws {
        #expect(UUID(uuidString: C.uuid()) != nil)
        let noon = Date(timeIntervalSince1970: 1_763_553_600)
        #expect(C.timestamp(now: noon, timeZone: try #require(TimeZone(identifier: "America/New_York"))) == "2025-11-19T07:00:00-05:00")
        let passwords = (0..<50).map { _ in C.password() }
        #expect(Set(passwords).count == 50)
        for password in passwords {
            #expect(password.count == 20)
            #expect(password.contains(where: \.isLowercase) && password.contains(where: \.isUppercase))
            #expect(password.contains(where: \.isNumber) && password.contains(where: { "!#$%&*+-=?@^_~".contains($0) }))
        }
        #expect(C.loremIpsum.hasPrefix("Lorem ipsum"))
    }
}
