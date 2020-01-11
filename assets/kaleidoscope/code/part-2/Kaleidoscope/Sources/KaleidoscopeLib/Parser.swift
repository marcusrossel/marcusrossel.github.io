// MARK: - Parser

public final class Parser<Tokens: TokenStream> where Tokens.Token == Token {
 
    public struct Error: Swift.Error {
        public let unexpectedToken: Token?
    }
    
    private var tokens: Tokens
    private var currentToken: Token?
 
    public init(tokens: Tokens) {
        self.tokens = tokens
    }
    
    private func consumeToken() throws {
        currentToken = try tokens.nextToken()
    }
    
    private func consumeToken(_ target: Token) throws {
        guard currentToken == target else { throw Error(unexpectedToken: currentToken) }
        try consumeToken()
    }
    
    public func parseProgram() throws -> Program {
        try consumeToken()
        var program = Program()
        
        while currentToken != nil {
            switch currentToken {
            case .keyword(.external):
                program.externals.append(try parseExternalFunction())
            case .keyword(.definition):
                program.functions.append(try parseFunction())
            default:
                program.expressions.append(try parseExpression())
            }
        }
        
        return program
    }
}

// MARK: - Parsing Helper Methods

extension Parser {
 
    private func parseTuple<Element>(parsingFunction parseElement: () throws -> Element) throws -> [Element] {
        try consumeToken(.symbol(.leftParenthesis))
        var elements: [Element] = []
 
        while (try? consumeToken(.symbol(.rightParenthesis))) == nil {
            let element = try parseElement()
            elements.append(element)
 
            if currentToken == .symbol(.rightParenthesis) {
                continue
            } else if currentToken != .symbol(.comma) {
                throw Error(unexpectedToken: currentToken)
            } else {
                try! consumeToken() // know to be `.symbol(.comma)`
                guard currentToken != .symbol(.rightParenthesis) else {
                    throw Error(unexpectedToken: currentToken)
                }
            }
        }
 
        return elements
    }
    
    private func parseIdentifier() throws -> String {
        guard case let .identifier(identifier)? = currentToken else {
            throw Error(unexpectedToken: currentToken)
        }
        
        try! consumeToken() // known to be `.identifier`
        return identifier
    }
}

// MARK: - Expression Parsing Methods

extension Parser {
    
    private func parseExpression() throws -> Expression {
        var expression: Expression
        
        switch currentToken {
        case .symbol(.leftParenthesis):
            expression = try parseParenthesizedExpression()
        case .number:
            expression = try parseNumberExpression()
        case .keyword(.if):
            expression = try parseIfExpression()
        case .identifier(let identifier):
            expression = (try? parseCallExpression()) ?? .variable(identifier)
        default:
            throw Error(unexpectedToken: currentToken)
        }
        
        if let binaryExpression = try? parseBinaryExpression(lhs: expression) {
            expression = binaryExpression
        }
        
        return expression
    }
    
    private func parseParenthesizedExpression() throws -> Expression {
        try consumeToken(.symbol(.leftParenthesis))
        let innerExpression = try parseExpression()
        try consumeToken(.symbol(.rightParenthesis))
        
        return innerExpression
    }
    
    private func parseCallExpression() throws -> Expression {
        let identifier = try parseIdentifier()
        let arguments = try parseTuple(parsingFunction: parseExpression)
        
        return .call(identifier, arguments: arguments)
    }
    
    private func parseNumberExpression() throws -> Expression {
        guard case let .number(number)? = currentToken else {
            throw Error(unexpectedToken: currentToken)
        }
        
        try! consumeToken() // known to be `.numberLiteral`
        return .number(number)
    }
    
    private func parseIfExpression() throws -> Expression {
        try consumeToken(.keyword(.if))
        let condition = try parseExpression()
        try consumeToken(.keyword(.then))
        let then = try parseExpression()
        try consumeToken(.keyword(.else))
        let `else` = try parseExpression()
        
        return .if(condition: condition, then: then, else: `else`)
    }
    
    private func parseBinaryExpression(lhs: Expression) throws -> Expression {
        guard case let .operator(`operator`)? = currentToken else {
            throw Error(unexpectedToken: currentToken)
        }
        try! consumeToken() // known to be `.operator`
        
        let rhs = try parseExpression()
        
        return .binary(lhs: lhs, operator: `operator`, rhs: rhs)
    }
}

// MARK: - Function Parsing Methods

extension Parser {
    
    private func parsePrototype() throws -> Prototype {
        let identifier = try parseIdentifier()
        let parameters = try parseTuple(parsingFunction: parseIdentifier)
        
        return Prototype(name: identifier, parameters: parameters)
    }
    
    private func parseExternalFunction() throws -> Prototype {
        try consumeToken(.keyword(.external))
        let prototype = try parsePrototype()
        try consumeToken(.symbol(.semicolon))
        
        return prototype
    }
    
    private func parseFunction() throws -> Function {
        try consumeToken(.keyword(.definition))
        let prototype = try parsePrototype()
        let expression = try parseExpression()
        try consumeToken(.symbol(.semicolon))
        
        return Function(head: prototype, body: expression)
    }
}

// MARK: - AST

public struct Program {
    var externals: [Prototype] = []
    var functions: [Function] = []
    var expressions: [Expression] = []
}

public struct Prototype {
    let name: String
    let parameters: [String]
}

public struct Function {
    let head: Prototype
    let body: Expression
}

public indirect enum Expression {
    case number(Double)
    case variable(String)
    case binary(lhs: Expression, operator: Operator, rhs: Expression)
    case call(String, arguments: [Expression])
    case `if`(condition: Expression, then: Expression, else: Expression)
}

// MARK: - Token Stream

public protocol TokenStream {
 
    associatedtype Token
 
    mutating func nextToken() throws -> Token?
}

// MARK: - Conformances

extension Lexer: TokenStream { }

extension Program: Equatable { }
extension Prototype: Equatable { }
extension Function: Equatable { }
extension Expression: Equatable { }
