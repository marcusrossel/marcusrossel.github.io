import CLLVM

public final class IRGenerator {
 
    public private(set) var ast: Program
    public private(set) var module: LLVMModuleRef
    private let context: LLVMContextRef
    private let builder: LLVMBuilderRef
    private let floatType: LLVMTypeRef
    
    public init(ast: Program) {
        self.ast = ast
        module = LLVMModuleCreateWithName("kaleidoscope")
        context = LLVMContextCreate()
        builder = LLVMCreateBuilderInContext(context)
        floatType = LLVMFloatTypeInContext(context)
    }
}

// MARK: - Expression Parsing Methods

extension IRGenerator {
    
    private func generateNumberExpression(_ number: Double) -> LLVMValueRef {
        return LLVMConstReal(floatType, number)
    }
    
    private func generateBinaryExpression(
        lhs: Expression, operator: Operator, rhs: Expression
    ) throws -> LLVMValueRef {
        let lhs = try generateExpression(lhs)
        let rhs = try generateExpression(rhs)
        
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
    
        let entryBlock = LLVMGetInsertBlock(builder)
    }
    
}
