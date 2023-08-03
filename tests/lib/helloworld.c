#include "nimscr.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>

void my_error_hook(char *filename, intptr_t line, intptr_t col, char *msg,
                   intptr_t sev) {
  printf("%s\n", msg);
}
void testImpl(nimscripter_vm_args args) {
  intptr_t val = nimscripter_vmargsGetInt(args, 0);
  printf("We got: %ld\n", val);
}

int main() {
  nimscripter_vm_proc_signature_t testProc = {
      "testInput", "proc testInput(i: int) = discard", testImpl};
  nimscripter_addins_t addins = {&testProc, 1};
  nimscripter_errorHook = my_error_hook;
  char *modules = "json";

  const char *myScript = "echo %*{\"a\": \"Hello World\"}\n"
                         "proc doThing*(): int = echo \"Huh\";result = 30\n"
                         "proc doOtherThing*(a: int): string = $a\n"
                         "proc arrTest*(arr: openArray[int]): bool ="
                         "  echo arr; arr == [0, 1, 2, 3, 4]\n"
                         "testInput(100)";

  nimscripter_interpreter_t intr =
      nimscripter_loadString(myScript, addins, &modules, 1, 0, 0,
                             "/home/jason/.choosenim/toolchains/nim-#devel/lib",
                             &nimscripter_default_defines[0], 2);

  nimscripter_pnode_t ret = nimscripter_invoke(intr, "doThing", 0, 0);
  intptr_t myVal = 0;
  nimscripter_pnodeGetInt(ret, &myVal);

  printf("%ld\n", myVal);

  nimscripter_destroyPnode(ret);

  nimscripter_pnode_t input = nimscripter_intNode(500);

  assert(nimscripter_pnodeGetKind(ret) == nkIntLit);

  ret = nimscripter_invoke(intr, "doOtherThing", &input, 1);

  char *myStr = "";
  nimscripter_pnodeGetString(ret, &myStr);
  printf("%s\n", myStr);

  assert(nimscripter_pnodeGetKind(ret) == nkStrLit);
  nimscripter_destroyPnode(ret);
  nimscripter_destroyPnode(input);

  input = nimscripter_newNode(nkBracket);

  for (int i = 0; i < 5; i++) {
    nimscripter_pnodeAdd(input, nimscripter_intNode(i));
  }

  ret = nimscripter_invoke(intr, "arrTest", &input, 1);

  intptr_t passed = 0;
  assert(nimscripter_pnodeGetInt(ret, &passed) && (bool)passed);
  nimscripter_destroyPnode(ret);
  nimscripter_destroyPnode(input);

  nimscripter_destroyInterpreter(intr);
  return 0;
}
