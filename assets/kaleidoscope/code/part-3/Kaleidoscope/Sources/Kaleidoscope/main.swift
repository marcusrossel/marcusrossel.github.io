import KaleidoscopeLib
import CLLVM

let program = """
def double(x) 2 * x;
def is_equal(x, y) if x - y then 0 else 1;

double(3.5 + 2.5)
if is_equal(double(1), 2) then 100 else 0
"""

do {
    let lexer = Lexer(text: program)
    let parser = Parser(tokens: lexer)
    let ast = try parser.parseProgram()
    let irGenerator = IRGenerator(ast: ast)
    try irGenerator.generateProgram()
    LLVMDumpModule(irGenerator.module)
} catch {
    print(error)
}
