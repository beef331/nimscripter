#include <stdint.h>

typedef struct vm_args *nimscripter_vm_args;

typedef struct nimscripter_vm_proc_signature {
  char *name;
  char *runtime_impl;
  void (*vm_proc)(nimscripter_vm_args);

} nimscripter_vm_proc_signature_t;

typedef struct nimscripter_addins {
  nimscripter_vm_proc_signature_t *procs;
  intptr_t procs_len;
  char *additions;
  char *post_code_additions;

} nimscripter_addins_t;

typedef struct nimscripter_defines {
  char *left, *right;
} nimscripter_defines_t;

typedef struct intepreter *interpreter_t;

typedef void (*error_hook)(char *, intptr_t, intptr_t, char *, intptr_t);

static nimscripter_defines_t nimscripter_default_defines[2] = {
    {"nimscript", "true"}, {"nimconfig", "true"}};

extern error_hook *nimscripter_error_hook;

extern interpreter_t nimscripter_load_script(char *, nimscripter_addins_t,
                                             char **, intptr_t, char **,
                                             intptr_t, char *,
                                             nimscripter_defines_t *, intptr_t);

extern interpreter_t nimscripter_load_string(char *, nimscripter_addins_t,
                                             char **, intptr_t, char **,
                                             intptr_t, char *,
                                             nimscripter_defines_t *, intptr_t);

extern void nimscripter_destroy_interpreter(interpreter_t);
