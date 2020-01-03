import XCTest
@testable import KaleidoscopeLib

final class ParserTests: XCTestCase {

    static var allTests = [
        ("testNoTokens", testNoTokens),
    ]
    
    func testNoTokens() throws {
        let parser = Parser(tokens: Tokens())
    
        let program = try parser.parseProgram()
        
        XCTAssertEqual(program.expressions, [])
        XCTAssertEqual(program.externals, [])
        XCTAssertEqual(program.functions, [])
    }
}

// MARK: - Lexer Mocking

private struct Tokens: TokenStream {
    
    private var nextIndex = 0
    private let tokens: [Token]
    
    init(_ tokens: Token...) {
        self.tokens = tokens
    }
    
    mutating func nextToken() -> Token? {
        guard nextIndex < tokens.endIndex else { return nil }
        defer { nextIndex += 1 }
        return tokens[nextIndex]
    }
}

#warning("Not documented in post.")
private struct ThrowingStream: TokenStream {
    
    enum Error: Swift.Error {
        case test
    }
    
    func nextToken() throws -> Token? {
        throw Error.test
    }
}
