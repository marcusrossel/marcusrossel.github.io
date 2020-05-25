import KaleidoscopeLib
import CLLVM

do {
    let program = """
        def double(x) 2 * x;
        def is_equal(x, y) if x - y then 0 else 1;

        double(3.5 + 2.5)
        if is_equal(double(1), 2) then 100 else 0
        """
    
    let lexer = Lexer(text: program)
    let parser = Parser(tokens: lexer)
    let ast = try parser.parseProgram()
    let irGenerator = IRGenerator(ast: ast)

    try irGenerator.generateProgram()
    
    /*var verificationError: UnsafeMutablePointer<Int8>?
    let errorStatus = LLVMVerifyModule(irGenerator.module, LLVMReturnStatusAction, &verificationError)
    if let message = verificationError, errorStatus == LLVMBool(true) {
        print(String(cString: message))
        exit(1)
    }*/
    
    LLVMDumpModule(irGenerator.module)
} catch {
    print(error)
}

