import Foundation
import Testing
@testable import OpenShelf

struct CaseTransformsTests {
    typealias C = CaseTransforms

    @Test func upperAndLowerHandleUnicode() {
        #expect(C.upper("straße café\n") == "STRASSE CAFÉ\n")
        #expect(C.lower("ÉCOLE Ω\r\n") == "école ω\r\n")
        #expect(C.upper("") == "")
    }

    @Test func titleCapitalisesWordsAndKeepsInnerCapitals() {
        #expect(C.title("the lord of the rings") == "The Lord Of The Rings")
        #expect(C.title("my iPhone and NASA on eBay") == "My iPhone And NASA On eBay")
        #expect(C.title("'quoted' words") == "'Quoted' Words")
        #expect(C.title("2nd place") == "2nd Place")
        #expect(C.title("SHOUTING TEXT") == "Shouting Text")
        #expect(C.title("don't stop-me now\n") == "Don't Stop-Me Now\n")
        #expect(C.title("élan vital") == "Élan Vital")
    }

    @Test func sentenceCaseStartsSentencesAndParagraphs() {
        #expect(C.sentence("HELLO THERE. how ARE you? fine!") == "Hello there. How are you? Fine!")
        #expect(C.sentence("first line\nsame sentence\n\nnew paragraph") == "First line\nsame sentence\n\nNew paragraph")
        #expect(C.sentence("v1.2 is out") == "V1.2 is out")
        #expect(C.sentence("") == "")
        #expect(C.sentence("ÉTÉ CHAUD.\r\n\r\nnouveau") == "Été chaud.\r\n\r\nNouveau")
    }

    @Test(arguments: [
        ("hello world", ["hello", "world"]),
        ("fooBarBaz", ["foo", "Bar", "Baz"]),
        ("HTTPServer", ["HTTP", "Server"]),
        ("parseJSON", ["parse", "JSON"]),
        ("version2Update", ["version2", "Update"]),
        ("snake_case-and kebab", ["snake", "case", "and", "kebab"]),
        ("CONSTANT_VALUE", ["CONSTANT", "VALUE"]),
        ("  --  ", []),
        ("naïveCafé", ["naïve", "Café"]),
    ])
    func wordsSplitIdentifiersAndPhrases(text: String, words: [String]) {
        #expect(C.words(text) == words)
    }

    @Test func identifierCasesFromAnyStyle() {
        for text in ["user id count", "userIdCount", "UserIdCount", "user_id_count", "user-id-count", "USER_ID_COUNT", "User ID count"] {
            #expect(C.camel(text) == "userIdCount", "\(text)")
            #expect(C.pascal(text) == "UserIdCount", "\(text)")
            #expect(C.snake(text) == "user_id_count", "\(text)")
            #expect(C.kebab(text) == "user-id-count", "\(text)")
            #expect(C.constant(text) == "USER_ID_COUNT", "\(text)")
        }
    }

    @Test func identifierCasesWorkLineByLine() {
        #expect(C.snake("First Name\n  lastName  \n\n") == "first_name\n  last_name  \n\n")
        #expect(C.camel("a b\r\nc d\r\n") == "aB\r\ncD\r\n")
        #expect(C.kebab("") == "")
        #expect(C.pascal("---") == "---")
        #expect(C.camel("HTTPServer") == "httpServer")
    }
}
