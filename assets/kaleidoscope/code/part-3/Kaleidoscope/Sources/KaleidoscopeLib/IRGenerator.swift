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
            /* lhs:       */ try generateExpression(condition),
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
        var phiValues: [LLVMValueRef?] = [try generateExpression(then), try generateExpression(`else`)]
        var phiBlocks = [thenBlock, elseBlock]
        LLVMAddIncoming(phiNode, &phiValues, &phiBlocks, 2)
        
        return phiNode
    }
    
    func generateExpression(_ e: Expression) throws -> LLVMValueRef {
        
    }
    
}
