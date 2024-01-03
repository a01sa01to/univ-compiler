%{
/**
   The cmm compiler
   2004.08.18
   2005.06.13
   Hisashi Nakai, University of Tsukuba
**/

#include <stdio.h>
#include <stdlib.h>

#include "env.h"
#include "code.h"

FILE *ofile;

int level = 0;
int offset = 0;

int mod_label = -1;
int pow_label = -1;


typedef struct Codeval {
  cptr* code;
  int   val;
  char* name;
} codeval;

#define YYSTYPE codeval
%}

%token VAR
%token MAIN
%token ID
%token LPAR RPAR
%token COMMA
%token LBRA RBRA
%token WRITE
%token WRITELN
%token SEMI
%token PLUS MINUS
%token PLUS2 MINUS2
%token MULT DIV MOD
%token POW
%token NUMBER
%token IF THEN ELSE ENDIF
%token WHILE DO
%token READ
%token COLEQ
%token GOTO COL
%token GE GT LE LT NE EQ
%token RETURN

%%

program:
    fdecls main {
      cptr *tmp;
      int label0;

      label0 = makelabel();

      tmp = makecode(O_JMP, 0, label0);
      tmp = mergecode(tmp, $1.code);
      tmp = mergecode(tmp, makecode(O_LAB, 0, label0));
      tmp = mergecode(tmp, makecode(O_INT, 0, $2.val + SYSTEM_AREA));
      tmp = mergecode(tmp, $2.code);
      tmp = mergecode(tmp, makecode(O_OPR, 0, 0));

      printcode(ofile, tmp);
    }
  ;


main:
    MAIN body {
      $$.code = $2.code;
      $$.val = $2.val;
    }
  ;


fdecls:
    fdecls fdecl {
      $$.code = mergecode($1.code, $2.code);
    }
  |
    /* epsilon */ {
      $$.code = NULL;
    }
  ;


fdecl:
    fhead body {
      cptr *tmp, *tmp2;

      tmp = makecode(O_LAB, 0, $1.val);
      tmp2 = makecode(O_INT, 0, $2.val + SYSTEM_AREA);
      $$.code = mergecode(mergecode(tmp, tmp2), $2.code);
      delete_block();
    }
  ;


fhead:
    fid LPAR params RPAR {
      int   label;
      int   i;
      list *tmp;

      tmp = search_all($1.name);
      if (tmp->kind == FUNC) {
        label = tmp->a;
      }

      make_params($3.val+1, label);

      $$.val = label;
    }
  ;


fid:
    ID {
      list* tmp = search_all($1.name);
      if (tmp == NULL){
        addlist($1.name, FUNC, makelabel(), level, 0);
      }
      else if (tmp->kind == REF_FUNC) {
        tmp->kind = FUNC;
      }
      else {
        sem_error1("fid");
      }
      addlist("block", BLOCK, 0, 0, 0);
    }
  ;


params:
    params COMMA ID {
      if (search_block($3.name) == NULL){
        addlist($3.name, VARIABLE, 0, level, 0);
      }
      else {
        sem_error1("params");
      }

      $$.code = NULL;
      $$.val = $1.val + 1;
    }
  |
    ID {
      if (search_block($1.name) == NULL){
        addlist($1.name, VARIABLE, 0, level, 0);
      }
      else {
        sem_error1("params2");
      }

      $$.code = NULL;
      $$.val = 1;
    }
  |
    /* epsilon */ {
      $$.val = 0;
      $$.code = NULL;
    }
  ;


body:
    LBRA vdaction stmts RBRA {
      $$.code = $3.code;
      $$.val = $2.val + $3.val;
      offset = offset - $2.val;
    }
  ;


vdaction:
    vardecls {
      int i;
      vd_backpatch($1.val, offset);

      $$.val = $1.val;
      offset = offset + $1.val;
    }
  ;


vardecls:
    vardecls vardecl {
      $$.val = $1.val + $2.val;
      $$.code = NULL;
    }
  |
    /* epsilon */ {
      $$.val = 0;
    }
  ;


vardecl:
    VAR ids SEMI {
      $$.val = $2.val;
      $$.code = NULL;
    }
  ;


ids:
    ids COMMA ID {
      if (search_block($3.name) == NULL){
        addlist($3.name, VARIABLE, 0, level, 0);
      }
      else {
        sem_error1("var");
      }

      $$.code = NULL;
      $$.val = $1.val + 1;
    }
  |
    ID {
      if (search_block($1.name) == NULL){
        addlist($1.name, VARIABLE, 0, level, 0);
      }
      else {
        sem_error1("var");
      }

      $$.code = NULL;
      $$.val = 1;
    }
  ;

stmts:
    stmts st {
      $$.code = mergecode($1.code, $2.code);
      if ($1.val < $2.val){
        $$.val = $2.val;
      }
      else {
        $$.val = $1.val;
      }
    }
  |
    st {
      $$.code = $1.code;
      $$.val = $1.val;
    }
  ;


st:
    WRITE E SEMI {
      $$.code = mergecode($2.code, makecode(O_CSP, 0, 1));
      $$.val = 0;
    }
  |
    WRITELN SEMI {
      $$.code = makecode(O_CSP, 0, 2);
      $$.val = 0;
    }
  |
    READ ID SEMI {
      cptr *tmp;
      list *tmp2;

      tmp2 = search_all($2.name);

      if (tmp2 == NULL){
        sem_error2("read");
      }

      if (tmp2->kind != VARIABLE){
        sem_error2("as function");
      }

      $$.code = mergecode(
        makecode(O_CSP, 0, 0),
        makecode(O_STO, level - tmp2->l, tmp2->a)
      );
      $$.val = 0;
    }
  |
    ID COLEQ E SEMI {
      list *tmp;

      tmp = search_all($1.name);

      if (tmp == NULL){
        sem_error2("assignment");
      }

      if (tmp->kind != VARIABLE){
        sem_error2("assignment2");
      }

      $$.code = mergecode(
        $3.code,
        makecode(O_STO, level - tmp->l, tmp->a)
      );
      $$.val = 0;
    }
  |
    ifstmt
  |
    whilestmt
  |
    { addlist("block", BLOCK, 0, 0, 0); }
    body {
      $$.code = $2.code;
      $$.val = $2.val;
      delete_block();
    }
  |
    RETURN E SEMI {
      list* tmp2;

      tmp2 = searchf(level);

      $$.code = mergecode($2.code, makecode(O_RET, 0, tmp2->params));
      $$.val = 0;
    }
  |
    GOTO ID SEMI {
      int label;

      list* tmp = search_block($2.name);
      if (tmp == NULL) {
        label = makelabel();
        addlist($2.name, REF_LABEL, label, 0, 0);
      }
      else {
        label = tmp->a;
      }

      $$.code = makecode(O_JMP, 0, label);
    }
  |
    ID COL {
      int label;

      list* tmp = search_block($1.name);
      if (tmp == NULL) {
        label = makelabel();
        addlist($1.name, LABEL, label, 0, 0);
      }
      else if (tmp->kind == REF_LABEL) {
        tmp->kind = LABEL;
        label = tmp->a;
      }
      else {
        sem_error1("label");
      }

      $$.code = makecode(O_LAB, 0, label);
    }
  ;


ifstmt:
    IF cond THEN st ENDIF SEMI {
      cptr *tmp;
      int label0, label1;

      label0 = makelabel();

      tmp = mergecode($2.code, makecode(O_JPC, 0, label0));
      tmp = mergecode(tmp, $4.code);

      $$.code = mergecode(tmp, makecode(O_LAB, 0, label0));
      $$.val = 0;
    }
  |
    IF cond THEN st ELSE st ENDIF SEMI {
      cptr *tmp;
      int label0, label1;

      label0 = makelabel();
      label1 = makelabel();

      tmp = mergecode($2.code, makecode(O_JPC, 0, label0));
      tmp = mergecode(tmp, $4.code);
      tmp = mergecode(tmp, makecode(O_JMP, 0, label1));
      tmp = mergecode(tmp, makecode(O_LAB, 0, label0));
      tmp = mergecode(tmp, $6.code);

      $$.code = mergecode(tmp, makecode(O_LAB, 0, label1));
      $$.val = 0;
    }
  ;


whilestmt:
    WHILE cond DO st {
      int label0, label1;
      cptr *tmp;

      label0 = makelabel();
      label1 = makelabel();

      tmp = makecode(O_LAB, 0, label0);
      tmp = mergecode(tmp, $2.code);
      tmp = mergecode(tmp, makecode(O_JPC, 0, label1));
      tmp = mergecode(tmp, $4.code);
      tmp = mergecode(tmp, makecode(O_JMP, 0, label0));
      tmp = mergecode(tmp, makecode(O_LAB, 0, label1));

      $$.code = tmp;

      $$.val = 0;
    }
  ;


cond:
    E GT E {
      $$.code = mergecode(
        mergecode($1.code, $3.code),
        makecode(O_OPR, 0, 12)
      );
    }
  |
    E GE E {
      $$.code = mergecode(
        mergecode($1.code, $3.code),
        makecode(O_OPR, 0, 11)
      );
    }
  |
    E LT E {
      $$.code = mergecode(
        mergecode($1.code, $3.code),
        makecode(O_OPR, 0, 10)
      );
    }
  |
    E LE E {
      $$.code = mergecode(
        mergecode($1.code, $3.code),
        makecode(O_OPR, 0, 13)
      );
    }
  |
    E NE E {
      $$.code = mergecode(
        mergecode($1.code, $3.code),
        makecode(O_OPR, 0, 9)
      );
    }
  |
    E EQ E {
      $$.code = mergecode(
        mergecode($1.code, $3.code),
        makecode(O_OPR, 0, 8)
      );
    }
  ;


E:
    E PLUS T {
      $$.code = mergecode(
        mergecode($1.code, $3.code),
        makecode(O_OPR, 0, 2)
      );
    }
  |
    E MINUS T {
      $$.code = mergecode(
        mergecode($1.code, $3.code),
        makecode(O_OPR, 0, 3)
      );
    }
  |
    T {
      $$.code = $1.code;
    }
  ;


T:
    T MULT FC {
      $$.code = mergecode(
        mergecode($1.code, $3.code),
        makecode(O_OPR, 0, 4)
      );
    }
  |
    T DIV FC {
      $$.code = mergecode(
        mergecode($1.code, $3.code),
        makecode(O_OPR, 0, 5)
      );
    }
  |
    T MOD FC {
      cptr *tmp;
      tmp = mergecode($1.code, $3.code); // a b

      if (mod_label == -1) {
        mod_label = makelabel();
        int mod_after = makelabel();

        tmp = mergecode(tmp, makecode(O_CAL, 0, mod_label));
        tmp = mergecode(tmp, makecode(O_JMP, 0, mod_after));

        tmp = mergecode(tmp, makecode(O_LAB, 0, mod_label));
        tmp = mergecode(tmp, makecode(O_INT, 0, SYSTEM_AREA));
        tmp = mergecode(tmp, makecode(O_LOD, 0, -2)); // a
        tmp = mergecode(tmp, makecode(O_LOD, 0, -2)); // a a
        tmp = mergecode(tmp, makecode(O_LOD, 0, -1)); // a a b
        tmp = mergecode(tmp, makecode(O_OPR, 0, 5));  // a a/b
        tmp = mergecode(tmp, makecode(O_LOD, 0, -1)); // a a/b b
        tmp = mergecode(tmp, makecode(O_OPR, 0, 4));  // a a/b*b
        tmp = mergecode(tmp, makecode(O_OPR, 0, 3));  // a%b
        tmp = mergecode(tmp, makecode(O_RET, 0, 2));

        tmp = mergecode(tmp, makecode(O_LAB, 0, mod_after));
      }
      else {
        tmp = mergecode(tmp, makecode(O_CAL, 0, mod_label));
      }

      $$.code = tmp;
    }
  |
    FC {
      $$.code = $1.code;
    }
  ;


FC:
    FC POW F {
      cptr *tmp;
      tmp = mergecode($1.code, $3.code); // a b

      if (pow_label == -1) {
        pow_label = makelabel();
        int pow_after = makelabel();
        int while_start = makelabel();
        int while_end = makelabel();
        int even_jmp = makelabel();

        tmp = mergecode(tmp, makecode(O_CAL, 0, pow_label));
        tmp = mergecode(tmp, makecode(O_JMP, 0, pow_after));

        tmp = mergecode(tmp, makecode(O_LAB, 0, pow_label));
        tmp = mergecode(tmp, makecode(O_INT, 0, SYSTEM_AREA));
        tmp = mergecode(tmp, makecode(O_LOD, 0, -2)); // a 3
        tmp = mergecode(tmp, makecode(O_LOD, 0, -1)); // x 4
        tmp = mergecode(tmp, makecode(O_LIT, 0, 1)); // ret 5

        tmp = mergecode(tmp, makecode(O_LAB, 0, while_start));
        // if x <= 0 end
        tmp = mergecode(tmp, makecode(O_LOD, 0, 4));
        tmp = mergecode(tmp, makecode(O_LIT, 0, 0));
        tmp = mergecode(tmp, makecode(O_OPR, 0, 12));
        tmp = mergecode(tmp, makecode(O_JPC, 0, while_end));

        // if x % 2 == 1 ret = ret * a
        tmp = mergecode(tmp, makecode(O_LOD, 0, 4));
        tmp = mergecode(tmp, makecode(O_OPR, 0, 6));
        tmp = mergecode(tmp, makecode(O_JPC, 0, even_jmp));
        tmp = mergecode(tmp, makecode(O_LOD, 0, 5));
        tmp = mergecode(tmp, makecode(O_LOD, 0, 3));
        tmp = mergecode(tmp, makecode(O_OPR, 0, 4));
        tmp = mergecode(tmp, makecode(O_STO, 0, 5));

        // a = a * a
        tmp = mergecode(tmp, makecode(O_LAB, 0, even_jmp));
        tmp = mergecode(tmp, makecode(O_LOD, 0, 3));
        tmp = mergecode(tmp, makecode(O_LOD, 0, 3));
        tmp = mergecode(tmp, makecode(O_OPR, 0, 4));
        tmp = mergecode(tmp, makecode(O_STO, 0, 3));

        // x = x / 2
        tmp = mergecode(tmp, makecode(O_LOD, 0, 4));
        tmp = mergecode(tmp, makecode(O_LIT, 0, 2));
        tmp = mergecode(tmp, makecode(O_OPR, 0, 5));
        tmp = mergecode(tmp, makecode(O_STO, 0, 4));

        tmp = mergecode(tmp, makecode(O_JMP, 0, while_start));

        tmp = mergecode(tmp, makecode(O_LAB, 0, while_end));
        tmp = mergecode(tmp, makecode(O_RET, 0, 2));

        tmp = mergecode(tmp, makecode(O_LAB, 0, pow_after));
      }
      else {
        tmp = mergecode(tmp, makecode(O_CAL, 0, pow_label));
      }

      $$.code = tmp;
    }
  |
    F {
      $$.code = $1.code;
    }


F:
    ID {
      cptr *tmpc;
      list* tmpl;

      tmpl = search_all($1.name);
      if (tmpl == NULL){
        sem_error2("id");
      }

      if (tmpl->kind == VARIABLE){
        $$.code = makecode(O_LOD, level - tmpl->l, tmpl->a);
      }
      else {
        sem_error2("id as variable");
      }
    }
  |
    ID PLUS2 {
      cptr *tmpc;
      list* tmpl;

      tmpl = search_all($1.name);
      if (tmpl == NULL){
        sem_error2("id");
      }

      if (tmpl->kind == VARIABLE){
        tmpc = makecode(O_LOD, level - tmpl->l, tmpl->a);
        tmpc = mergecode(tmpc, makecode(O_LOD, level - tmpl->l, tmpl->a));
        tmpc = mergecode(tmpc, makecode(O_LIT, 0, 1));
        tmpc = mergecode(tmpc, makecode(O_OPR, 0, 2));
        tmpc = mergecode(tmpc, makecode(O_STO, level - tmpl->l, tmpl->a));
        $$.code = tmpc;
      }
      else {
        sem_error2("id as variable");
      }
    }
  |
    PLUS2 ID {
      cptr *tmpc;
      list* tmpl;

      tmpl = search_all($1.name);
      if (tmpl == NULL){
        sem_error2("id");
      }

      if (tmpl->kind == VARIABLE){
        tmpc = makecode(O_LOD, level - tmpl->l, tmpl->a);
        tmpc = mergecode(tmpc, makecode(O_LIT, 0, 1));
        tmpc = mergecode(tmpc, makecode(O_OPR, 0, 2));
        tmpc = mergecode(tmpc, makecode(O_STO, level - tmpl->l, tmpl->a));
        tmpc = mergecode(tmpc, makecode(O_LOD, level - tmpl->l, tmpl->a));
        $$.code = tmpc;
      }
      else {
        sem_error2("id as variable");
      }
    }
  |
    ID LPAR fparams RPAR {
      list* tmpl;

      tmpl = search_all($1.name);
      if (tmpl == NULL){
        // block で消されるので、 block 前に追加しておく
        list* tmp = gettail();
        while (tmp != NULL && tmp->kind != BLOCK) tmp = tmp->prev;
        list* newl = (list*) malloc(sizeof(list));
        if (newl == NULL){
          perror("malloc");
          exit(EXIT_FAILURE);
        }
        newl->name = $1.name;
        newl->kind = REF_FUNC;
        newl->a = makelabel();
        newl->l = 0;
        newl->params = $3.val;
        newl->prev = tmp->prev;
        tmp->prev = newl;

        tmpl = newl;
      }

      if (tmpl->kind != FUNC && tmpl->kind != REF_FUNC){
        sem_error2("id as function2");
      }

      if (tmpl->params != $3.val){
        sem_error3(tmpl->name, tmpl->params, $3.val);
      }

      $$.code = mergecode(
        $3.code,
        makecode(O_CAL, level - tmpl->l, tmpl->a)
      );
    }
  |
    NUMBER {
      $$.code = makecode(O_LIT, 0, yylval.val);
    }
  |
    LPAR E RPAR {
      $$.code = $2.code;
    }
  ;


fparams:
    /* epsilon */ {
      $$.val = 0;
      $$.code = NULL;
    }
  |
    ac_params {
      $$.val = $1.val;
      $$.code = $1.code;
    }
  ;


ac_params:
    ac_params COMMA fparam {
      $$.val = $1.val + 1;
      $$.code = mergecode($1.code, $3.code);
    }
  |
    fparam {
      $$.val = 1;
      $$.code = $1.code;
    }
  ;


fparam:
    E {
      $$.code = $1.code;
    }
  ;

%%

#include "lex.yy.c"

main(){
  ofile = fopen("code.output", "w");

  if (ofile == NULL){
    perror("ofile");
    exit(EXIT_FAILURE);
  }

  initialize();
  yyparse();

  // Check if the label is defined
  list* tmp = gettail();
  while (tmp != NULL) {
    if (tmp->kind == REF_LABEL) {
      fprintf(stderr,"label %s is referenced but not defined\n", tmp->name);
      exit(EXIT_FAILURE);
    }
    if (tmp->kind == REF_FUNC) {
      fprintf(stderr,"function %s is referenced but not defined\n", tmp->name);
      exit(EXIT_FAILURE);
    }
    tmp = tmp->prev;
  }

  if (fclose(ofile) != 0){
    perror("ofile");
    exit(EXIT_FAILURE);
  }
}
