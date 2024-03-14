#include <stdbool.h>
#include <stdint.h>

enum nimscripter_Severity {
  nimscripter_Hint = 0,
  nimscripter_Warning = 1,
  nimscripter_Error = 2
};

struct nimscripter_Version {
  uint8_t major;
  uint8_t minor;
  uint8_t patch;
};

struct nimscripter_opaque_Inter;

struct nimscripter_string_data {
  intptr_t capacity;
  char data[];
};

struct nimscripter_string {
  intptr_t len;
  struct nimscripter_string_data *data;
};

struct nimscripter_WrappedInterpreter {
  struct nimscripter_opaque_Inter *intr;
  struct nimscripter_string path;
  struct nimscripter_string tempBuffer;
};

struct nimscripter_opaque_PNode;

struct nimscripter_TLineInfo {
  uint16_t line;
  int16_t col;
  int32_t fileIndex;
};

enum nimscripter_TRegisterKind {
  nimscripter_rkNone = 0,
  nimscripter_rkNode = 1,
  nimscripter_rkInt = 2,
  nimscripter_rkFloat = 3,
  nimscripter_rkRegisterAddr = 4,
  nimscripter_rkNodeAddr = 5
};

struct nimscripter_TFullReg {
  enum nimscripter_TRegisterKind kind;
};

struct nimscripter_VmArgs {
  intptr_t ra;
  intptr_t rb;
  intptr_t rc;
  struct nimscripter_TFullReg *slots;
  struct nimscripter_opaque_PNode *currentException;
  struct nimscripter_TLineInfo currentLineInfo;
};

struct nimscripter_VmProcSignature {
  char *package;
  char *name;
  char *module;
  void (*vmProc)(struct nimscripter_VmArgs *);
};

struct nimscripter_VmAddins {
  struct nimscripter_VmProcSignature *procs;
  intptr_t procLen;
  char *additions;
  char *postCodeAdditions;
};

struct nimscripter_Defines {
  char *left;
  char *right;
};

enum nimscripter_TNodeKind {
  nimscripter_nkNone = 0,
  nimscripter_nkEmpty = 1,
  nimscripter_nkIdent = 2,
  nimscripter_nkSym = 3,
  nimscripter_nkType = 4,
  nimscripter_nkCharLit = 5,
  nimscripter_nkIntLit = 6,
  nimscripter_nkInt8Lit = 7,
  nimscripter_nkInt16Lit = 8,
  nimscripter_nkInt32Lit = 9,
  nimscripter_nkInt64Lit = 10,
  nimscripter_nkUIntLit = 11,
  nimscripter_nkUInt8Lit = 12,
  nimscripter_nkUInt16Lit = 13,
  nimscripter_nkUInt32Lit = 14,
  nimscripter_nkUInt64Lit = 15,
  nimscripter_nkFloatLit = 16,
  nimscripter_nkFloat32Lit = 17,
  nimscripter_nkFloat64Lit = 18,
  nimscripter_nkFloat128Lit = 19,
  nimscripter_nkStrLit = 20,
  nimscripter_nkRStrLit = 21,
  nimscripter_nkTripleStrLit = 22,
  nimscripter_nkNilLit = 23,
  nimscripter_nkComesFrom = 24,
  nimscripter_nkDotCall = 25,
  nimscripter_nkCommand = 26,
  nimscripter_nkCall = 27,
  nimscripter_nkCallStrLit = 28,
  nimscripter_nkInfix = 29,
  nimscripter_nkPrefix = 30,
  nimscripter_nkPostfix = 31,
  nimscripter_nkHiddenCallConv = 32,
  nimscripter_nkExprEqExpr = 33,
  nimscripter_nkExprColonExpr = 34,
  nimscripter_nkIdentDefs = 35,
  nimscripter_nkVarTuple = 36,
  nimscripter_nkPar = 37,
  nimscripter_nkObjConstr = 38,
  nimscripter_nkCurly = 39,
  nimscripter_nkCurlyExpr = 40,
  nimscripter_nkBracket = 41,
  nimscripter_nkBracketExpr = 42,
  nimscripter_nkPragmaExpr = 43,
  nimscripter_nkRange = 44,
  nimscripter_nkDotExpr = 45,
  nimscripter_nkCheckedFieldExpr = 46,
  nimscripter_nkDerefExpr = 47,
  nimscripter_nkIfExpr = 48,
  nimscripter_nkElifExpr = 49,
  nimscripter_nkElseExpr = 50,
  nimscripter_nkLambda = 51,
  nimscripter_nkDo = 52,
  nimscripter_nkAccQuoted = 53,
  nimscripter_nkTableConstr = 54,
  nimscripter_nkBind = 55,
  nimscripter_nkClosedSymChoice = 56,
  nimscripter_nkOpenSymChoice = 57,
  nimscripter_nkHiddenStdConv = 58,
  nimscripter_nkHiddenSubConv = 59,
  nimscripter_nkConv = 60,
  nimscripter_nkCast = 61,
  nimscripter_nkStaticExpr = 62,
  nimscripter_nkAddr = 63,
  nimscripter_nkHiddenAddr = 64,
  nimscripter_nkHiddenDeref = 65,
  nimscripter_nkObjDownConv = 66,
  nimscripter_nkObjUpConv = 67,
  nimscripter_nkChckRangeF = 68,
  nimscripter_nkChckRange64 = 69,
  nimscripter_nkChckRange = 70,
  nimscripter_nkStringToCString = 71,
  nimscripter_nkCStringToString = 72,
  nimscripter_nkAsgn = 73,
  nimscripter_nkFastAsgn = 74,
  nimscripter_nkGenericParams = 75,
  nimscripter_nkFormalParams = 76,
  nimscripter_nkOfInherit = 77,
  nimscripter_nkImportAs = 78,
  nimscripter_nkProcDef = 79,
  nimscripter_nkMethodDef = 80,
  nimscripter_nkConverterDef = 81,
  nimscripter_nkMacroDef = 82,
  nimscripter_nkTemplateDef = 83,
  nimscripter_nkIteratorDef = 84,
  nimscripter_nkOfBranch = 85,
  nimscripter_nkElifBranch = 86,
  nimscripter_nkExceptBranch = 87,
  nimscripter_nkElse = 88,
  nimscripter_nkAsmStmt = 89,
  nimscripter_nkPragma = 90,
  nimscripter_nkPragmaBlock = 91,
  nimscripter_nkIfStmt = 92,
  nimscripter_nkWhenStmt = 93,
  nimscripter_nkForStmt = 94,
  nimscripter_nkParForStmt = 95,
  nimscripter_nkWhileStmt = 96,
  nimscripter_nkCaseStmt = 97,
  nimscripter_nkTypeSection = 98,
  nimscripter_nkVarSection = 99,
  nimscripter_nkLetSection = 100,
  nimscripter_nkConstSection = 101,
  nimscripter_nkConstDef = 102,
  nimscripter_nkTypeDef = 103,
  nimscripter_nkYieldStmt = 104,
  nimscripter_nkDefer = 105,
  nimscripter_nkTryStmt = 106,
  nimscripter_nkFinally = 107,
  nimscripter_nkRaiseStmt = 108,
  nimscripter_nkReturnStmt = 109,
  nimscripter_nkBreakStmt = 110,
  nimscripter_nkContinueStmt = 111,
  nimscripter_nkBlockStmt = 112,
  nimscripter_nkStaticStmt = 113,
  nimscripter_nkDiscardStmt = 114,
  nimscripter_nkStmtList = 115,
  nimscripter_nkImportStmt = 116,
  nimscripter_nkImportExceptStmt = 117,
  nimscripter_nkExportStmt = 118,
  nimscripter_nkExportExceptStmt = 119,
  nimscripter_nkFromStmt = 120,
  nimscripter_nkIncludeStmt = 121,
  nimscripter_nkBindStmt = 122,
  nimscripter_nkMixinStmt = 123,
  nimscripter_nkUsingStmt = 124,
  nimscripter_nkCommentStmt = 125,
  nimscripter_nkStmtListExpr = 126,
  nimscripter_nkBlockExpr = 127,
  nimscripter_nkStmtListType = 128,
  nimscripter_nkBlockType = 129,
  nimscripter_nkWith = 130,
  nimscripter_nkWithout = 131,
  nimscripter_nkTypeOfExpr = 132,
  nimscripter_nkObjectTy = 133,
  nimscripter_nkTupleTy = 134,
  nimscripter_nkTupleClassTy = 135,
  nimscripter_nkTypeClassTy = 136,
  nimscripter_nkStaticTy = 137,
  nimscripter_nkRecList = 138,
  nimscripter_nkRecCase = 139,
  nimscripter_nkRecWhen = 140,
  nimscripter_nkRefTy = 141,
  nimscripter_nkPtrTy = 142,
  nimscripter_nkVarTy = 143,
  nimscripter_nkConstTy = 144,
  nimscripter_nkOutTy = 145,
  nimscripter_nkDistinctTy = 146,
  nimscripter_nkProcTy = 147,
  nimscripter_nkIteratorTy = 148,
  nimscripter_nkSinkAsgn = 149,
  nimscripter_nkEnumTy = 150,
  nimscripter_nkEnumFieldDef = 151,
  nimscripter_nkArgList = 152,
  nimscripter_nkPattern = 153,
  nimscripter_nkHiddenTryStmt = 154,
  nimscripter_nkClosure = 155,
  nimscripter_nkGotoState = 156,
  nimscripter_nkState = 157,
  nimscripter_nkBreakState = 158,
  nimscripter_nkFuncDef = 159,
  nimscripter_nkTupleConstr = 160,
  nimscripter_nkError = 161,
  nimscripter_nkModuleRef = 162,
  nimscripter_nkReplayAction = 163,
  nimscripter_nkNilRodNode = 164
};

struct nimscripter_opaque_SaveState;

extern void (*nimscripter_errorHook)(char *, intptr_t, intptr_t, char *,
                                     enum nimscripter_Severity);
extern struct nimscripter_Version nimscripter_version;
extern bool nimscripter_do_log;

struct nimscripter_WrappedInterpreter nimscripter_dafuq();
struct nimscripter_WrappedInterpreter
nimscripter_load_script(char *script, struct nimscripter_VmAddins *addins,
                        char **searchPaths_data, intptr_t searchPaths_len,
                        char *stdPath, struct nimscripter_Defines *defines_data,
                        intptr_t defines_len);
void nimscripter_reload_script(struct nimscripter_WrappedInterpreter *intr,
                               bool keepBest);
struct nimscripter_opaque_PNode *
nimscripter_new_node(enum nimscripter_TNodeKind kind);
void nimscripter_pnode_add(struct nimscripter_opaque_PNode *node,
                           struct nimscripter_opaque_PNode *toAdd);
struct nimscripter_opaque_PNode *nimscripter_int_node(intptr_t val);
struct nimscripter_opaque_PNode *nimscripter_int8_node(int8_t val);
struct nimscripter_opaque_PNode *nimscripter_int16_node(int16_t val);
struct nimscripter_opaque_PNode *nimscripter_int32_node(int32_t val);
struct nimscripter_opaque_PNode *nimscripter_int64_node(intptr_t val);
struct nimscripter_opaque_PNode *nimscripter_uint_node(uintptr_t val);
struct nimscripter_opaque_PNode *nimscripter_uint8_node(uint8_t val);
struct nimscripter_opaque_PNode *nimscripter_uint16_node(uint16_t val);
struct nimscripter_opaque_PNode *nimscripter_uint32_node(uint32_t val);
struct nimscripter_opaque_PNode *nimscripter_uint64_node(uintptr_t val);
struct nimscripter_opaque_PNode *nimscripter_float_node(float val);
struct nimscripter_opaque_PNode *nimscripter_double_node(double val);
struct nimscripter_opaque_PNode *nimscripter_string_node(char *val);
struct nimscripter_opaque_PNode *
nimscripter_pnode_index(struct nimscripter_opaque_PNode *val, intptr_t ind);
struct nimscripter_opaque_PNode *
nimscripter_pnode_index_field(struct nimscripter_opaque_PNode *val,
                              intptr_t ind);
bool nimscripter_pnode_get_int(struct nimscripter_opaque_PNode *val,
                               intptr_t *dest);
bool nimscripter_pnode_get_double(struct nimscripter_opaque_PNode *val,
                                  double *dest);
bool nimscripter_pnode_get_float(struct nimscripter_opaque_PNode *val,
                                 float *dest);
bool nimscripter_pnode_get_string(struct nimscripter_opaque_PNode *val,
                                  char **dest);
struct nimscripter_opaque_PNode *
nimscripter_invoke(struct nimscripter_WrappedInterpreter *intr, char *name,
                   struct nimscripter_opaque_PNode **args_data,
                   intptr_t args_len);
struct nimscripter_opaque_PNode *
nimscripter_invoke_node_name(struct nimscripter_WrappedInterpreter *intr,
                             struct nimscripter_opaque_PNode *name,
                             struct nimscripter_opaque_PNode **args_data,
                             intptr_t args_len);
enum nimscripter_TNodeKind
nimscripter_pnode_get_kind(struct nimscripter_opaque_PNode *node);
enum nimscripter_TRegisterKind
nimscripter_vmargs_get_kind(struct nimscripter_VmArgs *args, intptr_t i);
intptr_t nimscripter_vmargs_get_int(struct nimscripter_VmArgs *args,
                                    intptr_t i);
bool nimscripter_vmargs_get_bool(struct nimscripter_VmArgs *args, intptr_t i);
double nimscripter_vmargs_get_float(struct nimscripter_VmArgs *args,
                                    intptr_t i);
struct nimscripter_opaque_PNode *
nimscripter_vmargs_get_node(struct nimscripter_VmArgs *args, intptr_t i);
char *nimscripter_vmargs_get_string(struct nimscripter_VmArgs *args,
                                    intptr_t i);
void nimscripter_vmargs_set_result_int(struct nimscripter_VmArgs *args,
                                       intptr_t val);
void nimscripter_vmargs_set_result_float(struct nimscripter_VmArgs *args,
                                         double val);
void nimscripter_vmargs_set_result_string(struct nimscripter_VmArgs *args,
                                          char *val);
void nimscripter_vmargs_set_result_node(struct nimscripter_VmArgs *args,
                                        struct nimscripter_opaque_PNode *val);
void nimscripter_destroy_save_state(struct nimscripter_opaque_PNode *pnode);
struct nimscripter_opaque_SaveState *
nimscripter_save_state(struct nimscripter_WrappedInterpreter *intr);
void nimscripter_load_state(struct nimscripter_WrappedInterpreter *intr,
                            struct nimscripter_opaque_SaveState *state);
void nimscripter_destroy_interpreter(
    struct nimscripter_WrappedInterpreter *intr);
void nimscripter_destroy_pnode(struct nimscripter_opaque_PNode *pnode);
