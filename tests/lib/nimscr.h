#include "nimscr_kinds.h"
#include <stdbool.h>
#include <stdint.h>

typedef struct pnode *nimscripter_pnode_t;
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

typedef struct intepreter *nimscripter_interpreter_t;

typedef void (*error_hook)(char *, intptr_t, intptr_t, char *, intptr_t);

static nimscripter_defines_t nimscripter_default_defines[2] = {
    {"nimscript", "true"}, {"nimconfig", "true"}};

extern error_hook *nimscripter_error_hook;

extern nimscripter_interpreter_t
nimscripter_load_script(char *, nimscripter_addins_t, char **, intptr_t,
                        char **, intptr_t, char *, nimscripter_defines_t *,
                        intptr_t);

extern nimscripter_interpreter_t
nimscripter_load_string(char *, nimscripter_addins_t, char **, intptr_t,
                        char **, intptr_t, char *, nimscripter_defines_t *,
                        intptr_t);

extern void nimscripter_destroy_interpreter(nimscripter_interpreter_t);

extern nimscripter_pnode_t nimscripter_new_node(uint8_t);

extern void nimscripter_pnode_add(nimscripter_pnode_t, nimscripter_pnode_t);

extern nimscripter_pnode_t nimscripter_int_node(intptr_t);
extern nimscripter_pnode_t nimscripter_int8_node(int8_t);
extern nimscripter_pnode_t nimscripter_int16_node(int16_t);
extern nimscripter_pnode_t nimscripter_int32_node(int32_t);
extern nimscripter_pnode_t nimscripter_int64_node(int64_t);

extern nimscripter_pnode_t nimscripter_uint_node(uintptr_t);
extern nimscripter_pnode_t nimscripter_uint8_node(uint8_t);
extern nimscripter_pnode_t nimscripter_uint16_node(uint16_t);
extern nimscripter_pnode_t nimscripter_uint32_node(uint32_t);
extern nimscripter_pnode_t nimscripter_uint64_node(uint64_t);

extern nimscripter_pnode_t nimscripter_float_node(float);
extern nimscripter_pnode_t nimscripter_double_node(double);

extern nimscripter_pnode_t nimscripter_string_node(char *);

extern nimscripter_pnode_t nimscripter_pnode_index(nimscripter_pnode_t,
                                                   intptr_t);
extern nimscripter_pnode_t nimscripter_pnode_index_field(nimscripter_pnode_t,
                                                         intptr_t);

extern bool nimscripter_pnode_get_int(nimscripter_pnode_t, intptr_t *);

extern bool nimscripter_pnode_get_double(nimscripter_pnode_t, double *);
extern bool nimscripter_pnode_get_float(nimscripter_pnode_t, float *);

extern bool nimscripter_pnode_get_string(nimscripter_pnode_t, char **);

extern uint8_t nimscripter_pnode_get_kind(nimscripter_pnode_t);

extern void nimscripter_destroy_pnode(nimscripter_pnode_t);

extern nimscripter_pnode_t nimscripter_invoke(nimscripter_interpreter_t, char *,
                                              nimscripter_pnode_t *, intptr_t);
