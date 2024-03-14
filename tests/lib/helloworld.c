#include "nimscr.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>

static struct nimscripter_Defines nimscripter_default_defines[2] = {
    {"nimscript", "true"}, {"nimconfig", "true"}};

void my_error_hook(char *filename, intptr_t line, intptr_t col, char *msg,
                   enum nimscripter_Severity sev) {
  printf("%s\n", msg);
}
void testImpl(struct nimscripter_VmArgs *args) {
  intptr_t val = nimscripter_vmargs_get_int(args, 0);
  printf("We got: %ld\n", val);
}

int main() {
  nimscripter_do_log = true;
  struct nimscripter_VmProcSignature testProc = {
      "testscript", "testInput", "hooks", testImpl};
  struct nimscripter_VmAddins addins = {&testProc, 1};
  nimscripter_errorHook = my_error_hook;

  char *searchPaths[] = {"tests/lib", "tests/lib/scriptdir"};
  struct nimscripter_WrappedInterpreter intr = nimscripter_load_script(
      "tests/lib/testscript.nims", &addins, searchPaths, 2,
      "/home/jason/.choosenim/toolchains/nim-2.0.2/lib",
      &nimscripter_default_defines[0], 2);

  struct nimscripter_opaque_PNode *ret = nimscripter_invoke(&intr, "doThing", 0, 0);
  intptr_t myVal = 0;
  nimscripter_pnode_get_int(ret, &myVal);

  printf("%ld\n", myVal);

  nimscripter_destroy_pnode(ret);

  struct nimscripter_opaque_PNode *input = nimscripter_int_node(500);

  assert(nimscripter_pnode_get_kind(ret) == nimscripter_nkIntLit);

  ret = nimscripter_invoke(&intr, "doOtherThing", &input, 1);

  char *myStr = "";
  nimscripter_pnode_get_string(ret, &myStr);
  printf("%s\n", myStr);

  assert(nimscripter_pnode_get_kind(ret) == nimscripter_nkStrLit);
  nimscripter_destroy_pnode(ret);
  nimscripter_destroy_pnode(input);

  input = nimscripter_new_node(nimscripter_nkBracket);

  for (int i = 0; i < 5; i++) {
    nimscripter_pnode_add(input, nimscripter_int_node(i));
  }

  ret = nimscripter_invoke(&intr, "arrTest", &input, 1);

  intptr_t passed = 0;
  assert(nimscripter_pnode_get_int(ret, &passed) && (bool)passed);
  nimscripter_destroy_pnode(ret);
  nimscripter_destroy_pnode(input);

  nimscripter_destroy_interpreter(&intr);
  return 0;
}
