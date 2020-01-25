import XCTest
@testable import KaleidoscopeLib

final class LexerTests: XCTestCase {

    static var allTests = [
        ("testEmptyText", testEmptyText),
        ("testWhitespace", testWhitespace),
        ("testInvalidCharacters", testInvalidCharacters),
        ("testSpecialSymbols", testSpecialSymbols),
        ("testOperators", testOperators),
        ("testIdentifiersAndKeywords", testIdentifiersAndKeywords),
        ("testNumbers", testNumbers),
        ("testComplex", testComplex),
    ]
    
    func testEmptyText() {
        let lexer = Lexer(text: "")
        XCTAssertNil(try lexer.nextToken())
    }

    func testWhitespace() {
        let lexer = Lexer(text: "   \n ")
        XCTAssertNil(try lexer.nextToken())
    }
    
    func testInvalidCharacters() {
        let lexer = Lexer(text: "?! a")

        XCTAssertThrowsError(try lexer.nextToken())
        XCTAssertThrowsError(try lexer.nextToken())
        XCTAssertNotNil(try lexer.nextToken())
        XCTAssertNil(try lexer.nextToken())
    }
    
    func testSpecialSymbols() {
        let lexer = Lexer(text: "( ) : , ;")

        XCTAssertEqual(try lexer.nextToken(), .symbol(.leftParenthesis))
        XCTAssertEqual(try lexer.nextToken(), .symbol(.rightParenthesis))
        XCTAssertThrowsError(try lexer.nextToken())
        XCTAssertEqual(try lexer.nextToken(), .symbol(.comma))
        XCTAssertEqual(try lexer.nextToken(), .symbol(.semicolon))
        XCTAssertNil(try lexer.nextToken())
    }

    func testOperators() {
        let lexer = Lexer(text: "+-*/%")

        XCTAssertEqual(try lexer.nextToken(), .operator(.plus))
        XCTAssertEqual(try lexer.nextToken(), .operator(.minus))
        XCTAssertEqual(try lexer.nextToken(), .operator(.times))
        XCTAssertEqual(try lexer.nextToken(), .operator(.divide))
        XCTAssertEqual(try lexer.nextToken(), .operator(.modulo))
        XCTAssertNil(try lexer.nextToken())
    }

    func testIdentifiersAndKeywords() {
        let lexer = Lexer(text: "_012 _def def0 define def extern if then else")

        XCTAssertEqual(try lexer.nextToken(), .identifier("_012"))
        XCTAssertEqual(try lexer.nextToken(), .identifier("_def"))
        XCTAssertEqual(try lexer.nextToken(), .identifier("def0"))
        XCTAssertEqual(try lexer.nextToken(), .identifier("define"))
        XCTAssertEqual(try lexer.nextToken(), .keyword(.definition))
        XCTAssertEqual(try lexer.nextToken(), .keyword(.external))
        XCTAssertEqual(try lexer.nextToken(), .keyword(.if))
        XCTAssertEqual(try lexer.nextToken(), .keyword(.then))
        XCTAssertEqual(try lexer.nextToken(), .keyword(.else))
        XCTAssertNil(try lexer.nextToken())
    }

    func testNumbers() {
        let lexer = Lexer(text: "0 -123 3.14 42. .50 123_456")

        XCTAssertEqual(try lexer.nextToken(), .number(0))
        XCTAssertEqual(try lexer.nextToken(), .operator(.minus))
        XCTAssertEqual(try lexer.nextToken(), .number(123))
        XCTAssertEqual(try lexer.nextToken(), .number(3.14))
        XCTAssertEqual(try lexer.nextToken(), .number(42))
        XCTAssertThrowsError(try lexer.nextToken())
        XCTAssertThrowsError(try lexer.nextToken())
        XCTAssertEqual(try lexer.nextToken(), .number(50))
        XCTAssertEqual(try lexer.nextToken(), .number(123))
        XCTAssertNotNil(try lexer.nextToken())
        XCTAssertNil(try lexer.nextToken())
    }

    func testComplex() {
        let lexer = Lexer(text: "def_function.extern (123*x^4.5\nifthenelse;else\t")

        XCTAssertEqual(try lexer.nextToken(), .identifier("def_function"))
        XCTAssertThrowsError(try lexer.nextToken())
        XCTAssertEqual(try lexer.nextToken(), .keyword(.external))
        XCTAssertEqual(try lexer.nextToken(), .symbol(.leftParenthesis))
        XCTAssertEqual(try lexer.nextToken(), .number(123))
        XCTAssertEqual(try lexer.nextToken(), .operator(.times))
        XCTAssertEqual(try lexer.nextToken(), .identifier("x"))
        XCTAssertThrowsError(try lexer.nextToken())
        XCTAssertEqual(try lexer.nextToken(), .number(4.5))
        XCTAssertEqual(try lexer.nextToken(), .identifier("ifthenelse"))
        XCTAssertEqual(try lexer.nextToken(), .symbol(.semicolon))
        XCTAssertEqual(try lexer.nextToken(), .keyword(.else))
        XCTAssertNil(try lexer.nextToken())
    }
}
