#include "nimscr.h"
#include <stdint.h>
#include <stdio.h>

void my_error_hook(char *filename, intptr_t line, intptr_t col, char *msg,
                   intptr_t sev) {
  printf("%s\n", msg);
}

int main() {
  nimscripter_addins_t addins = {};
  nimscripter_error_hook = my_error_hook;
  char *modules = "json";

  const char *myScript = "echo %*{\"a\": \"Hello World\"}\n"
                         "proc doThing*(): int = echo \"Huh\";result = 30\n"
                         "proc doOtherThing*(a: int): string = $a\n";

  nimscripter_interpreter_t intr = nimscripter_load_string(
      myScript, addins, &modules, 1, 0, 0,
      "/home/jason/.choosenim/toolchains/nim-#devel/lib",
      &nimscripter_default_defines[0], 2);

  nimscripter_pnode_t ret = nimscripter_invoke(intr, "doThing", 0, 0);
  intptr_t myVal = 0;
  nimscripter_pnode_get_int(ret, &myVal);

  printf("%ld\n", myVal);

  nimscripter_destroy_pnode(ret);

  nimscripter_pnode_t input = nimscripter_int_node(500);

  ret = nimscripter_invoke(intr, "doOtherThing", &input, 1);

  char *myStr = "";
  nimscripter_pnode_get_string(ret, &myStr);
  printf("%s\n", myStr);

  nimscripter_destroy_pnode(ret);
  nimscripter_destroy_pnode(input);

  nimscripter_destroy_interpreter(intr);
  return 0;
}
