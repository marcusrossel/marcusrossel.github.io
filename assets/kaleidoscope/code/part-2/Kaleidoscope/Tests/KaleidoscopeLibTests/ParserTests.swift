import XCTest
@testable import KaleidoscopeLib

final class ParserTests: XCTestCase {
    
    static var allTests = [
        ("testNoTokens", testNoTokens),
        ("testLexerError", testLexerError)
    ]
    
    func testNoTokens() throws {
        let tokens: LexerMock = []
        let parser = Parser(tokens: tokens)
        let program = try parser.parseProgram()
        
        XCTAssert(program.externals.isEmpty)
        XCTAssert(program.functions.isEmpty)
        XCTAssert(program.expressions.isEmpty)
    }
    
    func testLexerError() {
        let tokens: LexerMock = [nil]
        let parser = Parser(tokens: tokens)
        
        do {
            _ = try parser.parseProgram()
            XCTFail("Expected an error to be thrown.")
        } catch {
            XCTAssertTrue(error is LexerMock.Error)
        }
    }
    
    func testParsingNumberExpression() throws {
        let tokens: LexerMock = [.number(5)]
        let parser = Parser(tokens: tokens)
        let program = try parser.parseProgram()
        
        let expected: [Expression] = [.number(5)]
        XCTAssert(program.onlyContains(expressions: expected))
    }
    
    func testParsingCallExpressionWithoutParameters() throws {
        let tokens: LexerMock = [
            .identifier("run"),
            .symbol(.leftParenthesis),
            .symbol(.rightParenthesis)
        ]
        let parser = Parser(tokens: tokens)
        let program = try parser.parseProgram()
        
        let expected: [Expression] = [.call("run", arguments: [])]
        XCTAssert(program.onlyContains(expressions: expected))
    }
    
    func testParsingCallExpressionWithParameters() throws {
        let tokens: LexerMock = [
            .identifier("run"),
            .symbol(.leftParenthesis),
            .number(1),
            .symbol(.comma),
            .number(2),
            .symbol(.rightParenthesis)
        ]
        let parser = Parser(tokens: tokens)
        let program = try parser.parseProgram()
        
        let expected: [Expression] = [.call("run", arguments: [.number(1), .number(2)])]
        XCTAssert(program.onlyContains(expressions: expected))
    }
    
    func testParsingCallExpressionWithTrailingComma() {
        let tokens: LexerMock = [
            .identifier("run"),
            .symbol(.leftParenthesis),
            .number(1),
            .symbol(.comma),
            .symbol(.rightParenthesis)
        ]
        let parser = Parser(tokens: tokens)
        
        do {
            _ = try parser.parseProgram()
            XCTFail("Expected an error to be thrown.")
        } catch {
            if let error = error as? Parser<LexerMock>.Error {
                XCTAssertEqual(error.unexpectedToken, .symbol(.rightParenthesis))
            } else {
                XCTFail("Expected a `Parser.Error` to be thrown.")
            }
        }
    }
    
    func testIfElseExpression() throws {
        let tokens: LexerMock = [
            .keyword(.if),
            .number(0),
            .keyword(.then),
            .number(10),
            .keyword(.else),
            .number(20)
        ]
        let parser = Parser(tokens: tokens)
        let program = try parser.parseProgram()
        
        let expected: [Expression] = [.if(condition: .number(0), then: .number(10), else: .number(20))]
        XCTAssert(program.onlyContains(expressions: expected))
    }
    
    func testIfElseExpressionWithMultipleReturnExpressions() throws {
        let tokens: LexerMock = [
            .keyword(.if),
            .number(0),
            .keyword(.then),
            .number(10),
            .number(15),
            .keyword(.else),
            .number(20)
        ]
        let parser = Parser(tokens: tokens)
        
        do {
            _ = try parser.parseProgram()
            XCTFail("Expected an error to be thrown.")
        } catch {
            if let error = error as? Parser<LexerMock>.Error {
                XCTAssertEqual(error.unexpectedToken, .number(15))
            } else {
                XCTFail("Expected a `Parser.Error` to be thrown.")
            }
        }
    }
    
    func testComplexExpression() throws {
        
    }
}

// MARK: - Lexer Mocking

private struct LexerMock: TokenStream, ExpressibleByArrayLiteral {
    
    enum Error: Swift.Error {
        case mock
    }
    
    private var nextIndex = 0
    private let tokens: [Token?]
    
    init(arrayLiteral tokens: Token?...) {
        self.tokens = tokens
    }
    
    mutating func nextToken() throws -> Token? {
        guard nextIndex < tokens.endIndex else { return nil }
        defer { nextIndex += 1 }
        
        guard let token = tokens[nextIndex] else { throw Error.mock }
        return token
    }
}

// MARK: - Testing Helpers

private extension Program {
    
    func onlyContains(externals: [Prototype]) -> Bool {
        functions.isEmpty && expressions.isEmpty && (self.externals == externals)
    }
    
    func onlyContains(functions: [Function]) -> Bool {
        externals.isEmpty && expressions.isEmpty && (self.functions == functions)
    }
    
    func onlyContains(expressions: [Expression]) -> Bool {
        externals.isEmpty && functions.isEmpty && (self.expressions == expressions)
    }
}
