#include "nimscr.h"
#include <stdio.h>

void my_error_hook(char *filename, intptr_t line, intptr_t col, char *msg,
                   intptr_t sev) {
  printf("%s\n", msg);
}

int main() {
  nimscripter_addins_t addins = {};
  nimscripter_error_hook = my_error_hook;

  nimscripter_load_string("echo \"Hello World\"", addins, 0, 0, 0, 0,
                          "/home/jason/.choosenim/toolchains/nim-#devel/lib",
                          &nimscripter_default_defines[0], 2);

  return 0;
}
