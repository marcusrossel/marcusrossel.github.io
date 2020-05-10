import CLLVM

// MARK: - IR Generator

public final class IRGenerator {
 
    public enum Error: Swift.Error {
        case unknownVariable(name: String)
        case unknownFunction(name: String)
        case invalidNumberOfArguments(Int, expected: Int, functionName: String)
        case invalidRedeclarationOfFunction(String)
    }
    
    public private(set) var ast: Program
    public private(set) var module: LLVMModuleRef
    private let context: LLVMContextRef
    private let builder: LLVMBuilderRef
    private let floatType: LLVMTypeRef
    private var symbolTable: [String: LLVMValueRef] = [:]
    
    public init(ast: Program) {
        self.ast = ast
        module = LLVMModuleCreateWithName("kaleidoscope")
        context = LLVMContextCreate()
        builder = LLVMCreateBuilderInContext(context)
        floatType = LLVMFloatTypeInContext(context)
    }
}

// MARK: - Function Generator Methods

extension IRGenerator {
    
    @discardableResult
    private func generate(prototype: Prototype) throws -> LLVMValueRef {
        guard LLVMGetNamedFunction(module, prototype.name) == nil else {
            throw Error.invalidRedeclarationOfFunction(prototype.name)
        }
        
        var parameters = [LLVMTypeRef?](repeating: floatType, count: prototype.parameters.count)
        
        let signature = LLVMFunctionType(
            floatType,
            &parameters,
            UInt32(prototype.parameters.count),
            LLVMBool(false)
        )
        
        return LLVMAddFunction(module, prototype.name, signature)
    }
}

// MARK: - Expression Generator Methods

extension IRGenerator {
    
    private func generateNumberExpression(_ number: Double) -> LLVMValueRef {
        return LLVMConstReal(floatType, number)
    }
    
    private func generateBinaryExpression(
        lhs: Expression, operator: Operator, rhs: Expression
    ) throws -> LLVMValueRef {
        let lhs = try generate(expression: lhs)
        let rhs = try generate(expression: rhs)
        
        switch `operator` {
        case .plus:   return LLVMBuildFAdd(builder, lhs, rhs, "sum")
        case .minus:  return LLVMBuildFSub(builder, lhs, rhs, "difference")
        case .times:  return LLVMBuildFMul(builder, lhs, rhs, "product")
        case .divide: return LLVMBuildFDiv(builder, lhs, rhs, "quotient")
        case .modulo: return LLVMBuildFRem(builder, lhs, rhs, "remainder")
        }
    }
    
    private func generateIfElseExpression(
        condition: Expression, then: Expression, else: Expression
    ) throws -> LLVMValueRef {
        // Creates and arranges the required basic blocks.
        
        let entryBlock = LLVMGetInsertBlock(builder)
        
        let mergeBlock = LLVMInsertBasicBlockInContext(context, entryBlock, "merge")
        LLVMMoveBasicBlockAfter(mergeBlock, entryBlock)
        
        let elseBlock = LLVMInsertBasicBlockInContext(context, mergeBlock, "else")
        let thenBlock = LLVMInsertBasicBlockInContext(context, elseBlock, "then")
        let ifBlock =   LLVMInsertBasicBlockInContext(context, thenBlock, "if")
        
        LLVMBuildBr(builder, ifBlock)
        
        // Generates the if-block.
        
        LLVMPositionBuilderAtEnd(builder, ifBlock)
        
        let condition = LLVMBuildFCmp(
            /* builder:   */ builder,
            /* predicate: */ LLVMRealONE,
            /* lhs:       */ try generate(expression: condition),
            /* rhs:       */ LLVMConstReal(floatType, 0) /* = false */,
            /* label:     */ "condition"
        )
        
        LLVMBuildCondBr(builder, condition, thenBlock, elseBlock)
        
        // Generates the then-block.
        LLVMPositionBuilderAtEnd(builder, thenBlock)
        LLVMBuildBr(builder, mergeBlock)
        
        // Generates the else-block.
        LLVMPositionBuilderAtEnd(builder, elseBlock)
        LLVMBuildBr(builder, mergeBlock)
        
        // Generates the phi node.
        
        LLVMPositionBuilderAtEnd(builder, mergeBlock)
        
        let phiNode = LLVMBuildPhi(builder, floatType, "result")!
        var phiValues: [LLVMValueRef?] = [try generate(expression: then), try generate(expression: `else`)]
        var phiBlocks = [thenBlock, elseBlock]
        LLVMAddIncoming(phiNode, &phiValues, &phiBlocks, 2)
        
        return phiNode
    }
    
    private func generateVariableExpression(name: String) throws -> LLVMValueRef {
        guard let value = symbolTable[name] else { throw Error.unknownVariable(name: name) }
        return value
    }
    
    private func generateCallExpression(
        functionName: String, arguments: [Expression]
    ) throws -> LLVMValueRef {
        guard let function = LLVMGetNamedFunction(module, functionName) else {
            throw Error.unknownFunction(name: functionName)
        }
        
        let parameterCount = LLVMCountParams(function)
        
        guard parameterCount == arguments.count else {
            throw Error.invalidNumberOfArguments(
                arguments.count,
                expected: Int(parameterCount),
                functionName: functionName
            )
        }
        
        var arguments: [LLVMValueRef?] = try arguments.map(generate(expression:))
        
        return LLVMBuildCall(builder, function, &arguments, parameterCount, functionName)
    }
    
    private func generate(expression: Expression) throws -> LLVMValueRef {
        switch expression {
        case let .number(number):
            return generateNumberExpression(number)
        case let .binary(lhs: lhs, operator: `operator`, rhs: rhs):
            return try generateBinaryExpression(lhs: lhs, operator: `operator`, rhs: rhs)
        case let .if(condition: condition, then: then, else: `else`):
            return try generateIfElseExpression(condition: condition, then: then, else: `else`)
        case let .variable(name):
            return try generateVariableExpression(name: name)
        case let .call(functionName, arguments: arguments):
            return try generateCallExpression(functionName: functionName, arguments: arguments)
        }
    }
    
}
