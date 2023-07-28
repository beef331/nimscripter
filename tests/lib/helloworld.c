#include "nimscr.h"
#include <stdio.h>

void my_error_hook(char *filename, intptr_t line, intptr_t col, char *msg,
                   intptr_t sev) {
  printf("%s\n", msg);
}

int main() {
  nimscripter_addins_t addins = {};
  nimscripter_error_hook = my_error_hook;
  char *modules = "json";

  nimscripter_interpreter_t intr = nimscripter_load_string(
      "echo %*{\"a\": \"Hello World\"}\nproc doThing*(): int = echo \"huh\"",
      addins, &modules, 1, 0, 0,
      "/home/jason/.choosenim/toolchains/nim-#devel/lib",
      &nimscripter_default_defines[0], 2);

  nimscripter_pnode_t ret = nimscripter_invoke(intr, "doThing", 0, 0);

  nimscripter_destroy_pnode(ret);

  nimscripter_destroy_interpreter(intr);
  return 0;
}
