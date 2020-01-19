import Foundation

// MARK: - Lexer

public final class Lexer {

    private typealias TokenTransformation = (Lexer) -> () throws -> Token?
    
    /// The plain text, which will be lexed.
    public let text: String

    /// The position of the next relevant character in `text`.
    public private(set) var position: Int

    /// An ordered list of the token transformations, in the order in which they
    /// should be called by `nextToken`.
    private let transformations: [TokenTransformation] = [
        lexWhitespace,
        lexIdentifiersAndKeywords,
        lexNumbers,
        lexSpecialSymbolsAndOperators,
        lexInvalidCharacter
    ]
    
    /// The set of characters allowed as an identifier's head.
    private let identifierHead: CharacterSet

    /// The set of characters allowed as an identifier's body.
    private let identifierBody: CharacterSet
    
    /// Creates a lexer for the given text, with a starting position of `0`.
    public init(text: String) {
        self.text = text
        position = 0

        identifierHead = CharacterSet
            .letters
            .union(CharacterSet(charactersIn: "_"))
        identifierBody = identifierHead.union(.decimalDigits)
    }
    
    /// Returns the the next character in `text`.
    ///
    /// - Note: If `position` has reached `text`'s end index, `nil` is returned
    /// on every subsequent call.
    ///
    /// - Parameter peek: Determines whether or not the lexer's `position` will
    /// be affected or not.
    /// - Parameter stride: The offset from the current `position` of the
    /// returned character (must be >= 1). The `stride` also affects the amount
    /// by which `position` will be increased.
    private func nextCharacter(peek: Bool = false, stride: Int = 1) -> Character? {
        // Precondition.
        guard stride >= 1 else {
            fatalError("Lexer Error: \(#function): `stride` must be >= 0.\n")
        }

        // Because `position` always points to the "next relevant character", a
        // stride of `1` should result in the `nextCharacterIndex` being equal
        // to `position`. Therefore the `- 1` at the end.
        let nextCharacterIndex = position + stride - 1

        // Changing the value of `position` should only happen after we have
        // determined what our next character is. Therefore the `defer`.
        defer {
            // Only increases the `position` if we are not peeking.
            // If the new `position` would go beyond the `text`'s end index, it
            // is instead capped at the end index (`text.count`).
            // The new `position` is `position + stride` (without `- 1`),
            // because it has to point to the character after the one we are
            // returning during this method call.
            if !peek { position = min(position + stride, text.count) }
        }

        // If the `nextCharacterIndex` is out of bounds, return `nil`.
        guard nextCharacterIndex < text.count else { return nil }


        return text[text.index(text.startIndex, offsetBy: nextCharacterIndex)]
    }
    
    /// Tries to return the next token lexable from the `text`.
    /// If there is a syntactical error in the `text`, an error is thrown.
    /// If there are no more characters to be lexed, `nil` is returned.
    public func nextToken() throws -> Token? {
        for transformation in transformations {
            if let token = try transformation(self)() {
                return token
            }
        }

        return nil
    }
}

// MARK: - Token Transformations

extension Lexer {
    
    public enum Error: Swift.Error {
        case invalidCharacter(Character)
    }

    /// Treats any lexed character as invalid, and throws
    /// `Error.invalidCharacter`.
    /// If there are no characters to be lexed, `nil` is returned.
    private func lexInvalidCharacter() throws -> Token? {
        if let character = nextCharacter() {
            throw Error.invalidCharacter(character)
        } else {
            return nil
        }
    }
    
    /// Consumes whitespace (and newlines). Always returns `nil`.
    private func lexWhitespace() -> Token? {
        while nextCharacter(peek: true).isPartOf(.whitespacesAndNewlines) {
            _ = self.nextCharacter()
        }

        return nil
    }
    
    private func lexSpecialSymbolsAndOperators() -> Token? {
        guard let character = nextCharacter(peek: true) else { return nil }

        if let specialSymbol = Token.Symbol(rawValue: character) {
            _ = nextCharacter()
            return .symbol(specialSymbol)
        }

        if let `operator` = Operator(rawValue: character) {
            _ = nextCharacter()
            return .operator(`operator`)
        }

        return nil
    }
    
    private func lexIdentifiersAndKeywords() -> Token? {
        guard nextCharacter(peek: true).isPartOf(identifierHead) else {
            return nil
        }

        var buffer = "\(nextCharacter()!)"

        while nextCharacter(peek: true).isPartOf(identifierBody) {
            buffer.append(nextCharacter()!)
        }

        if let keyword = Token.Keyword(rawValue: buffer) {
            return .keyword(keyword)
        } else {
            return .identifier(buffer)
        }
    }
    
    private func lexNumbers() -> Token? {
        guard nextCharacter(peek: true).isPartOf(.decimalDigits) else {
            return nil
        }
        
        var buffer = "\(nextCharacter()!)"
        
        while nextCharacter(peek: true).isPartOf(.decimalDigits) {
            buffer.append(nextCharacter()!)
        }
        
        if nextCharacter(peek: true) == "." &&
            nextCharacter(peek: true, stride: 2).isPartOf(.decimalDigits)
        {
            buffer.append(".\(nextCharacter(stride: 2)!)")
            
            while nextCharacter(peek: true).isPartOf(.decimalDigits) {
                buffer.append(nextCharacter()!)
            }
        }
        
        guard let number = Double(buffer) else {
            fatalError("Lexer Error: \(#function): internal error.")
        }
        
        return .number(number)
    }
}

// MARK: - Token

public enum Token {
    
    case keyword(Keyword)
    case identifier(String)
    case number(Double)

    case `operator`(Operator)
    case symbol(Symbol)

    public enum Keyword: String {
        case `if`
        case then
        case `else`
        case definition = "def"
        case external = "extern"
    }

    public enum Symbol: Character {
        case leftParenthesis = "("
        case rightParenthesis = ")"
        case comma = ","
        case semicolon = ";"
    }
}

public enum Operator: Character {
    case plus = "+"
    case minus = "-"
    case times = "*"
    case divide = "/"
    case modulo = "%"
}

// MARK: - Conformances

extension Token: Equatable { }
extension Token.Keyword: Equatable { }
extension Token.Symbol: Equatable { }
extension Operator: Equatable { }

// MARK: - Extensions

extension Character {

    /// Indicates whether the given character set contains this character.
    func isPartOf(_ set: CharacterSet) -> Bool {
        return String(self).rangeOfCharacter(from: set) != nil
    }
}

extension Optional where Wrapped == Character {

    /// Indicates whether the given character set contains this character.
    /// If `self == nil` this is false.
    func isPartOf(_ set: CharacterSet) -> Bool {
        guard let self = self else { return false }
        return self.isPartOf(set)
    }
}
