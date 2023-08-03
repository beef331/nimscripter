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

extern error_hook *nimscripter_errorHook;

extern nimscripter_interpreter_t
nimscripter_loadScript(char *, nimscripter_addins_t, char **, intptr_t, char **,
                       intptr_t, char *, nimscripter_defines_t *, intptr_t);

extern nimscripter_interpreter_t
nimscripter_loadString(char *, nimscripter_addins_t, char **, intptr_t, char **,
                       intptr_t, char *, nimscripter_defines_t *, intptr_t);

extern void nimscripter_destroyInterpreter(nimscripter_interpreter_t);

extern nimscripter_pnode_t nimscripter_newNode(uint8_t);

extern void nimscripter_pnodeAdd(nimscripter_pnode_t, nimscripter_pnode_t);

extern nimscripter_pnode_t nimscripter_intNode(intptr_t);
extern nimscripter_pnode_t nimscripter_int8Node(int8_t);
extern nimscripter_pnode_t nimscripter_int16Node(int16_t);
extern nimscripter_pnode_t nimscripter_int32Node(int32_t);
extern nimscripter_pnode_t nimscripter_int64Node(int64_t);

extern nimscripter_pnode_t nimscripter_uintNode(uintptr_t);
extern nimscripter_pnode_t nimscripter_uint8Node(uint8_t);
extern nimscripter_pnode_t nimscripter_uint16Node(uint16_t);
extern nimscripter_pnode_t nimscripter_uint32Node(uint32_t);
extern nimscripter_pnode_t nimscripter_uint64Node(uint64_t);

extern nimscripter_pnode_t nimscripter_floatNode(float);
extern nimscripter_pnode_t nimscripter_doubleNode(double);

extern nimscripter_pnode_t nimscripter_stringNode(char *);

extern nimscripter_pnode_t nimscripter_pnodeIndex(nimscripter_pnode_t,
                                                  intptr_t);
extern nimscripter_pnode_t nimscripter_pnode_indexField(nimscripter_pnode_t,
                                                        intptr_t);

extern bool nimscripter_pnodeGetInt(nimscripter_pnode_t, intptr_t *);

extern bool nimscripter_pnodeGetDouble(nimscripter_pnode_t, double *);
extern bool nimscripter_pnodeGetFloat(nimscripter_pnode_t, float *);

extern bool nimscripter_pnodeGetString(nimscripter_pnode_t, char **);

extern uint8_t nimscripter_pnodeGetKind(nimscripter_pnode_t);

extern void nimscripter_destroyPnode(nimscripter_pnode_t);

extern nimscripter_pnode_t nimscripter_invoke(nimscripter_interpreter_t, char *,
                                              nimscripter_pnode_t *, intptr_t);

extern intptr_t nimscripter_vmargsGetInt(nimscripter_vm_args, intptr_t);
extern bool nimscripter_vmargsGetBool(nimscripter_vm_args, intptr_t);
extern double nimscripter_vmargsGetFloat(nimscripter_vm_args, intptr_t);
extern nimscripter_pnode_t nimscripter_vmargsGetNode(nimscripter_vm_args,
                                                     intptr_t);
extern char *nimscripter_vmargsGetString(nimscripter_vm_args, intptr_t);
