/* sdloberon.c - an SDL back end that writes Oberon-2 modules for poc
   (doc/developer/vms-sdl-interfaces.md, "Proposals, part 2: the
   generator").

   SDL/NOPARSE/LANGUAGE=OBERON=<file> <module>.SDI loads this image from
   SYS$SHARE and calls sdl$output with the tree it read (sdldef.h). Every
   SDL MODULE node in the tree becomes one Oberon module, all of them
   written to <file>, each starting with a line

     (*** FILE <NAME>.Mod ***)

   that tools/vax-sdl splits on. The DCL symbol SDLOBERON_SOURCE, if
   defined, says where the tree came from, for each module's banner.
   What it cannot transcribe it reports on SYS$OUTPUT, as lines starting
   "sdloberon:", and leaves a comment in the module saying why.

   Written in the style of sdlscm.c (~/Repos/myunsdl), for VAX C 3.2:
   K&R definitions, no prototypes. tools/sdloberon/sdlload.c runs it on
   atla over SDLDUMP's dumps of a tree, to try it before the guest. */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#ifdef vms
#include <descrip.h>
#endif
#include "sdldef.h"

#define TI2(n) ((struct Node *)(n)->typeinfo2)

/* a conditional's node type, which sdldef.h does not name; SDLDUMP
   prints it as "unknown", and sdlload makes that SDL$C_NODE_UNKNOWN */
#define NODE_CONDITIONAL 13

/* ---- growable text -------------------------------------------------- */

struct Text {
  char *s;
  int len, cap;
};

static void put(t, s)
  struct Text *t;
  char *s;
{
  int n;

  n = strlen(s);
  if (t->len + n + 1 > t->cap) {
    t->cap = (t->len + n + 1) * 2 + 1024;
    t->s = t->s ? realloc(t->s, t->cap) : malloc(t->cap);
  };
  strcpy(t->s + t->len, s);
  t->len += n;
}

static char line[2048];

/* ---- names ---------------------------------------------------------- */

/* s as a C string, in one of eight rotating buffers */
static char *str(p)
  struct sptr *p;
{
  static char buf[8][300];
  static int k = 0;
  int n;

  k = (k + 1) & 7;
  n = p->len;
  if (n < 0) n = 0;
  if (n > 299) n = 299;
  strncpy(buf[k], p->str, n);
  buf[k][n] = '\0';
  while (n > 0 && buf[k][n - 1] == ' ') buf[k][--n] = '\0';
  return buf[k];
}

static char *upper(s)
  char *s;
{
  char *p;

  for (p = s; *p; p++) *p = toupper(*p);
  return s;
}

static char *keywords[] = {"ARRAY", "BEGIN", "BY", "CASE", "CONST", "DIV",
  "DO", "ELSE", "ELSIF", "END", "EXIT", "FOR", "IF", "IMPORT", "IN", "IS",
  "LOOP", "MOD", "MODULE", "NIL", "OF", "OR", "POINTER", "PROCEDURE",
  "RECORD", "REPEAT", "RETURN", "THEN", "TO", "TYPE", "UNTIL", "VAR",
  "WHILE", "WITH", "SYSTEM", 0};

/* s, with a trailing _ if it is an Oberon keyword or SYSTEM */
static char *oberon_name(s)
  char *s;
{
  int i;

  for (i = 0; keywords[i]; i++)
    if (strcmp(s, keywords[i]) == 0) {
      strcat(s, "_");
      break;
    };
  return s;
}

/* the names a module declares, with each constant's value */
#define MAXNAMES 8000
static struct Name {
  char *name;
  int is_constant;
  int value;
} *names; /* MAXNAMES of them, allocated by sdl$output */
static int nnames;

static int find_name(s)
  char *s;
{
  int i;

  for (i = 0; i < nnames; i++)
    if (strcmp(names[i].name, s) == 0) return i;
  return -1;
}

static void add_name(s, is_constant, value)
  char *s;
  int is_constant, value;
{
  if (nnames < MAXNAMES) {
    names[nnames].name = malloc(strlen(s) + 1);
    strcpy(names[nnames].name, s);
    names[nnames].is_constant = is_constant;
    names[nnames].value = value;
    nnames++;
  };
}

/* ---- output state for one module ------------------------------------ */

static struct Text body;
static char module_name[64];
static char source[400];
static int problems;

#define SECTION_NONE 0
#define SECTION_CONST 1
#define SECTION_TYPE 2
#define SECTION_PROCEDURE 3
static int section;

static void report(s)
  char *s;
{
  printf("sdloberon: %s: %s\n", module_name, s);
  problems++;
}

/* text of a comment, made safe inside (* *): Oberon's comments nest */
static char *comment_text(p)
  struct sptr *p;
{
  static char buf[1100];
  int i, j, n;
  char c;

  n = p->len;
  if (n > 500) n = 500;
  j = 0;
  for (i = 0; i < n; i++) {
    c = p->str[i];
    if (c == '\t') c = ' ';
    if (c < ' ' || c > '~') c = '?'; /* VAX C's isprint passes Latin-1 */
    if (c == '*' && j > 0 && buf[j - 1] == '(') buf[j++] = ' ';
    if (c == ')' && j > 0 && buf[j - 1] == '*') buf[j++] = ' ';
    buf[j++] = c;
  };
  while (j > 0 && buf[j - 1] == ' ') j--;
  buf[j] = '\0';
  for (i = 0; buf[i] == ' '; i++);
  return buf + i;
}

/* the SDL comment on a node, as " (* ... *)", or "" */
static char *end_comment(n)
  struct Node *n;
{
  static char buf[1200];
  char *c;

  buf[0] = '\0';
  if (n->comment) {
    c = comment_text(n->comment);
    if (*c) sprintf(buf, " (* %s *)", c);
  };
  return buf;
}

/* comment lines waiting for the declaration they come before */
static struct Text pending;
static int pending_lines;

static void add_comment_line(n)
  struct Node *n;
{
  char *c;

  c = n->comment ? comment_text(n->comment) : "";
  if (pending_lines == 0 && *c == '\0') return;
  if (pending_lines > 0) put(&pending, "\n");
  put(&pending, c);
  pending_lines++;
}

static void flush_comments(indent)
  char *indent;
{
  char *s, *e;
  int first;

  if (pending_lines == 0) return;
  /* drop trailing empty lines */
  while (pending.len > 0 && (pending.s[pending.len - 1] == '\n'))
    pending.s[--pending.len] = '\0';
  first = 1;
  s = pending.s;
  while (s) {
    e = strchr(s, '\n');
    if (e) *e = '\0';
    if (first) {
      sprintf(line, "%s(* %s", indent, s);
      first = 0;
    } else if (*s)
      sprintf(line, "\n%s   %s", indent, s);
    else
      sprintf(line, "\n");
    put(&body, line);
    s = e ? e + 1 : 0;
  };
  put(&body, " *)\n");
  pending.len = 0;
  pending.s[0] = '\0';
  pending_lines = 0;
}

static void enter_section(s)
  int s;
{
  if (s == section && s == SECTION_PROCEDURE) put(&body, "\n");
  if (s != section) {
    if (s == SECTION_CONST) put(&body, "\n  CONST\n");
    else if (s == SECTION_TYPE) put(&body, "\n  TYPE\n");
    else put(&body, "\n");
    section = s;
  };
  flush_comments(s == SECTION_PROCEDURE ? "  " : "    ");
}

/* ---- constants ------------------------------------------------------ */

/* NAME* = value; once: a name already declared with the same value is
   left out, and with another value gets a comment */
static void constant(name, value, hex, comment)
  char *name, *comment;
  int value, hex;
{
  int i;
  char v[40];

  i = find_name(name);
  if (i >= 0) {
    if (!names[i].is_constant || names[i].value != value) {
      sprintf(line, "    (* %s = %d again, as in SDL: the first is kept *)\n",
              name, value);
      put(&body, line);
      sprintf(line, "%s is declared twice", name);
      report(line);
    };
    return;
  };
  add_name(name, 1, value);
  if (hex) {
    if (value < 0)
      sprintf(v, "0FFFFFFFF%08XH", value);
    else
      sprintf(v, "0%XH", value);
  } else
    sprintf(v, "%d", value);
  sprintf(line, "    %s* = %s;%s\n", name, v, comment);
  put(&body, line);
}

static void constant_node(n)
  struct Node *n;
{
  enter_section(SECTION_CONST);
  if (n->datatype == SDL$C_TYPE_CHARACTER) {
    sprintf(line, "    (* %s left out: a string constant *)\n", str(&n->name));
    put(&body, line);
    sprintf(line, "%s left out: a string constant", str(&n->name));
    report(line);
    return;
  };
  constant(str(&n->name), n->typeinfo,
           (n->sdl_flag_bits.flags & SDL$M_MASK) != 0, end_comment(n));
}

/* ---- aggregates: constants ------------------------------------------ */

static int is_item(n)
  struct Node *n;
{
  return n->type == SDL$C_NODE_ITEM;
}

static int is_fill(n)
  struct Node *n;
{
  return (n->sdl_flag_bits.flags & SDL$M_FILL) != 0;
}

/* $S_ for a bit field: its prefix and tag's S, and its naked name */
static char *size_name(n)
  struct Node *n;
{
  static char buf[100];
  char *tag;

  tag = str(&n->tag);
  sprintf(buf, "%s%s_%s", str(&n->prefix),
          (tag[0] && islower(tag[0])) ? "s" : "S", str(&n->naked));
  return buf;
}

/* the offset constant of each field of aggregate s, and $V_ of each bit
   field, the position counted from s's start: each item before it in s,
   a bit field its width and anything else its bytes. In a union each
   member starts at s's start. $S_, a size, as SDL's MACRO back end gives
   it (STARLET.MLB): a bit field's wider than a bit, in bits; a field's
   whose type does not say it, in bytes - more than one character, an
   array, a quadword or anything else not of 1, 2 or 4 bytes - but not a
   nested structure's or union's; the aggregate's own unless it is a
   filler (aggregate). */
static void member_constants(s)
  struct Node *s;
{
  struct Node *head, *m;
  int bit;

  bit = 0;
  head = s->child;
  if (!head) return;
  for (m = head->flink; m != head; m = m->flink) {
    if (!is_item(m)) continue;
    if (s->datatype == SDL$C_TYPE_UNION) bit = 0;
    if (m->datatype == SDL$C_TYPE_BITFIELD) {
      if (!is_fill(m)) {
        constant(str(&m->name), bit, 0, end_comment(m));
        if (m->fldsiz > 1) constant(size_name(m), m->fldsiz, 0, "");
      };
      bit += m->fldsiz;
    } else {
      if (!is_fill(m)) {
        constant(str(&m->name), m->offset, 0, end_comment(m));
        if (m->datatype != SDL$C_TYPE_STRUCTURE && m->datatype != SDL$C_TYPE_UNION
            && m->fldsiz > 0
            && ((m->sdl_flag_bits.flags & SDL$M_DIMEN)
                || (m->datatype == SDL$C_TYPE_CHARACTER && m->fldsiz > 1)
                || (m->datatype != SDL$C_TYPE_CHARACTER && m->fldsiz != 1 && m->fldsiz != 2 && m->fldsiz != 4)))
          constant(size_name(m), m->fldsiz, 0, "");
      };
      bit = (m->offset - s->offset + m->fldsiz) * 8;
      if (m->datatype == SDL$C_TYPE_STRUCTURE || m->datatype == SDL$C_TYPE_UNION)
        member_constants(m);
    };
  };
}

/* ---- aggregates: the record type ------------------------------------ */

#define MAXFIELDS 600
struct Field {
  char name[64];
  char type[100];
  int offset, size, align;
  int exported;
  char note[200];
};
static struct Field *fields, *copy; /* MAXFIELDS each, from sdl$output */
static int nfields, fills;

static struct Field *new_field(name, offset, size, exported)
  char *name;
  int offset, size, exported;
{
  struct Field *f;

  if (nfields >= MAXFIELDS) return &fields[MAXFIELDS - 1];
  f = &fields[nfields++];
  strcpy(f->name, name);
  f->offset = offset;
  f->size = size;
  f->exported = exported;
  f->type[0] = '\0';
  f->note[0] = '\0';
  f->align = 1;
  return f;
}

static void bytes(f)
  struct Field *f;
{
  sprintf(f->type, "ARRAY %d OF SYSTEM.BYTE", f->size);
  f->align = 1;
}

/* the Oberon type of a scalar of SDL type t, and its size and alignment
   (poc's: its size, at most 4); 0 if it has none */
static char *scalar_type(t, size, align)
  int t, *size, *align;
{
  *size = 0;
  switch (t) {
  case SDL$C_TYPE_BYTE: *size = 1; *align = 1; return "SYSTEM.INT8";
  case SDL$C_TYPE_BOOLEAN: *size = 1; *align = 1; return "SYSTEM.INT8";
  case SDL$C_TYPE_WORD: *size = 2; *align = 2; return "SYSTEM.INT16";
  case SDL$C_TYPE_LONGWORD: *size = 4; *align = 4; return "SYSTEM.INT32";
  case SDL$C_TYPE_QUADWORD: *size = 8; *align = 4; return "SYSTEM.INT64";
  case SDL$C_TYPE_ADDRESS: *size = 4; *align = 4; return "SYSTEM.ADDRESS";
  case SDL$C_TYPE_ENTRY: *size = 4; *align = 4; return "SYSTEM.ADDRESS";
  case SDL$C_TYPE_FFLOAT: *size = 4; *align = 4; return "REAL";
  case SDL$C_TYPE_GFLOAT: *size = 8; *align = 4; return "LONGREAL";
  case SDL$C_TYPE_CHARACTER: *size = 1; *align = 1; return "CHAR";
  };
  return 0;
}

/* t, an Oberon scalar type, as the CARD of its width when flags mark it
   unsigned (part 3, proposals 1 and 2) */
static char *unsigned_type(t, flags)
  char *t;
  int flags;
{
  if (!t || !(flags & SDL$M_UNSIGNED)) return t;
  if (strcmp(t, "SYSTEM.INT8") == 0) return "SYSTEM.CARD8";
  if (strcmp(t, "SYSTEM.INT16") == 0) return "SYSTEM.CARD16";
  if (strcmp(t, "SYSTEM.INT32") == 0) return "SYSTEM.CARD32";
  if (strcmp(t, "SYSTEM.INT64") == 0) return "SYSTEM.CARD64";
  return t;
}

/* a field's type from item m: a scalar, an array of them, characters,
   or bytes */
static void field_type(f, m)
  struct Field *f;
  struct Node *m;
{
  char *t;
  int size, align, count, element;

  count = 1;
  if (m->sdl_flag_bits.flags & SDL$M_DIMEN) count = m->hidim - m->lodim + 1;
  if (count < 1) count = 1;
  t = scalar_type(m->datatype, &size, &align);
  if (m->datatype != SDL$C_TYPE_BOOLEAN)
    t = unsigned_type(t, m->sdl_flag_bits.flags);
  element = m->fldsiz / count;
  if (m->datatype == SDL$C_TYPE_CHARACTER) {
    if (count == 1)
      sprintf(f->type, "ARRAY %d OF CHAR", element);
    else if (element == 1)
      sprintf(f->type, "ARRAY %d OF CHAR", count);
    else
      sprintf(f->type, "ARRAY %d, %d OF CHAR", count, element);
    f->align = 1;
  } else if (t && element == size && element * count == m->fldsiz) {
    if (count == 1) strcpy(f->type, t);
    else sprintf(f->type, "ARRAY %d OF %s", count, t);
    f->align = align;
  } else
    bytes(f);
  if (m->datatype == SDL$C_TYPE_BOOLEAN) strcpy(f->note, "boolean");
  else if (m->datatype == SDL$C_TYPE_DFLOAT) strcpy(f->note, "D floating");
  else if (m->datatype == SDL$C_TYPE_HFLOAT) strcpy(f->note, "H floating");
  else if (m->datatype == SDL$C_TYPE_OCTAWORD) strcpy(f->note, "octaword");
  /* noted only where the type does not say it */
  if ((m->sdl_flag_bits.flags & SDL$M_UNSIGNED) && !strstr(f->type, "CARD")) {
    if (f->note[0]) strcat(f->note, ", ");
    strcat(f->note, "unsigned");
  };
}

static int is_scalar(m)
  struct Node *m;
{
  int size, align;

  return scalar_type(m->datatype, &size, &align) != 0
    || m->datatype == SDL$C_TYPE_DFLOAT || m->datatype == SDL$C_TYPE_HFLOAT
    || m->datatype == SDL$C_TYPE_OCTAWORD;
}

/* does structure s hold a field that is not a bit field? */
static int has_fields(s)
  struct Node *s;
{
  struct Node *head, *m;

  head = s->child;
  if (!head) return 0;
  for (m = head->flink; m != head; m = m->flink)
    if (is_item(m)) {
      if (m->datatype == SDL$C_TYPE_STRUCTURE) {
        if (has_fields(m)) return 1;
      } else if (m->datatype != SDL$C_TYPE_BITFIELD)
        return 1;
    };
  return 0;
}

static void field_name(buf, m)
  char *buf;
  struct Node *m;
{
  if (is_fill(m)) sprintf(buf, "fill%d", ++fills);
  else strcpy(buf, str(&m->name));
}

/* the fields of structure s, flattened (part 2, proposal 5) */
static void flatten(s)
  struct Node *s;
{
  struct Node *head, *m, *c, *pick;
  struct Field *f;
  char name[64];
  int run, run_start, run_bits, bit;

  head = s->child;
  if (!head) return;
  run = 0;
  run_start = 0;
  run_bits = 0;
  bit = 0;
  for (m = head->flink; m != head; m = m->flink) {
    if (!is_item(m)) continue;
    if (m->datatype == SDL$C_TYPE_BITFIELD) {
      /* a run of bit fields: the bytes they cover */
      if (!run) {
        field_name(name, m);
        f = new_field(name, s->offset + bit / 8, 0, !is_fill(m));
        run = 1;
        run_start = bit;
        run_bits = 0;
      } else if (!f->exported && !is_fill(m)) {
        strcpy(f->name, str(&m->name));
        f->exported = 1;
      };
      run_bits += m->fldsiz;
      bit += m->fldsiz;
      f->size = (run_start % 8 + run_bits + 7) / 8;
      bytes(f);
      strcpy(f->note, "bit fields");
      continue;
    };
    run = 0;
    bit = (m->offset - s->offset + m->fldsiz) * 8;
    if (m->datatype == SDL$C_TYPE_UNION) {
      pick = 0;
      if (m->child)
        for (c = m->child->flink; c != m->child && !pick; c = c->flink)
          if (is_item(c) && c->fldsiz == m->fldsiz) {
            if (is_scalar(c)) pick = c;
            else if (c->datatype == SDL$C_TYPE_STRUCTURE && has_fields(c)
                     && !(c->sdl_flag_bits.flags & SDL$M_DIMEN)) pick = c;
          };
      if (pick && pick->datatype == SDL$C_TYPE_STRUCTURE)
        flatten(pick);
      else if (pick) {
        field_name(name, pick);
        f = new_field(name, pick->offset, pick->fldsiz, !is_fill(pick));
        field_type(f, pick);
      } else {
        field_name(name, m);
        f = new_field(name, m->offset, m->fldsiz, !is_fill(m));
        bytes(f);
        strcpy(f->note, "a union");
      };
    } else if (m->datatype == SDL$C_TYPE_STRUCTURE
               && !(m->sdl_flag_bits.flags & SDL$M_DIMEN))
      flatten(m);
    else if (m->fldsiz > 0) {
      field_name(name, m);
      f = new_field(name, m->offset, m->fldsiz, !is_fill(m));
      if (m->datatype == SDL$C_TYPE_STRUCTURE) {
        bytes(f);
        strcpy(f->note, "an array of structures");
      } else
        field_type(f, m);
    };
  };
}

/* poc's layout of the fields against SDL's offsets: a scalar SDL puts
   off its alignment becomes bytes, a gap a filler; anything else is a
   failure, its message in why */
static int lay_out(total, why, poc_size)
  int total, *poc_size;
  char *why;
{
  int i, n, pos, at, align, max_align;
  char name[64];

  n = 0;
  pos = 0;
  max_align = 1;
  for (i = 0; i < nfields; i++) {
    if (n >= MAXFIELDS - 2) {
      strcpy(why, "too many fields");
      return 0;
    };
    align = fields[i].align;
    at = (pos + align - 1) / align * align;
    if (fields[i].offset < pos) {
      sprintf(why, "%s at offset %d overlaps the field before it",
              fields[i].name, fields[i].offset);
      return 0;
    };
    if (fields[i].offset % align != 0) {
      sprintf(fields[i].note, "%s at offset %d, which poc would align",
              fields[i].type, fields[i].offset);
      bytes(&fields[i]);
      align = 1;
      at = pos;
    };
    if (fields[i].offset > at) {
      sprintf(name, "fill%d", ++fills);
      copy[n] = fields[i];
      strcpy(copy[n].name, name);
      copy[n].offset = pos;
      copy[n].size = fields[i].offset - pos;
      copy[n].exported = 0;
      copy[n].note[0] = '\0';
      bytes(&copy[n]);
      n++;
    };
    copy[n++] = fields[i];
    pos = fields[i].offset + fields[i].size;
    if (align > max_align) max_align = align;
  };
  if (pos < total) {
    sprintf(name, "fill%d", ++fills);
    strcpy(copy[n].name, name);
    copy[n].offset = pos;
    copy[n].size = total - pos;
    copy[n].exported = 0;
    copy[n].note[0] = '\0';
    bytes(&copy[n]);
    n++;
    pos = total;
  };
  if (pos > total) {
    sprintf(why, "its fields end at %d, past its size", pos);
    return 0;
  };
  *poc_size = (pos + max_align - 1) / max_align * max_align;
  for (i = 0; i < n; i++) fields[i] = copy[i];
  nfields = n;
  for (i = 0; i < nfields; i++)
    for (n = 0; n < i; n++)
      if (strcmp(fields[i].name, fields[n].name) == 0) {
        sprintf(why, "two fields are named %s", fields[i].name);
        return 0;
      };
  return 1;
}

static void aggregate(a)
  struct Node *a;
{
  char why[200], name[64];
  int i, poc_size, all_bits;
  struct Field *f;

  enter_section(SECTION_CONST);
  if (!is_fill(a)) constant(size_name(a), a->fldsiz, 0, "");
  member_constants(a);
  if (a->datatype == SDL$C_TYPE_UNION) return;
  nfields = 0;
  fills = 0;
  flatten(a);
  all_bits = 1;
  for (i = 0; i < nfields; i++)
    if (strcmp(fields[i].note, "bit fields") != 0) all_bits = 0;
  if (all_bits) return;
  strcpy(name, str(&a->name));
  if (find_name(name) >= 0) {
    sprintf(line, "type %s has the name of a constant: left out", name);
    report(line);
    return;
  };
  add_name(name, 0, 0);
  enter_section(SECTION_TYPE);
  if (!lay_out(a->fldsiz, why, &poc_size)) {
    sprintf(line, "    %s* = ARRAY %d OF SYSTEM.BYTE; (* not a record: %s *)\n",
            name, a->fldsiz, why);
    put(&body, line);
    sprintf(line, "%s is not a record: %s", name, why);
    report(line);
    return;
  };
  sprintf(line, "    %s* = RECORD (* %d bytes", name, a->fldsiz);
  put(&body, line);
  if (poc_size != a->fldsiz) {
    sprintf(line, ", which poc pads to %d", poc_size);
    put(&body, line);
  };
  put(&body, " *)\n");
  for (i = 0; i < nfields; i++) {
    f = &fields[i];
    sprintf(line, "      %s%s: %s%s", f->name, f->exported ? "*" : "", f->type,
            i < nfields - 1 ? ";" : "");
    put(&body, line);
    if (f->note[0]) {
      sprintf(line, " (* %s *)", f->note);
      put(&body, line);
    };
    put(&body, "\n");
  };
  put(&body, "    END;\n");
}

/* ---- entries -------------------------------------------------------- */

/* the node an address parameter's object points to: its typeinfo2 is a
   head, whose ring holds the object */
static struct Node *object(p)
  struct Node *p;
{
  struct Node *h, *o;

  h = TI2(p);
  if (!h) return 0;
  if (h->type != SDL$C_NODE_HEAD) return h;
  for (o = h->flink; o != h; o = o->flink)
    if (o->type == SDL$C_NODE_OBJECT) return o;
  return 0;
}

/* Oberon's formal for parameter p, into buf; 0 if there is no rule */
static int formal(p, number, buf, why)
  struct Node *p;
  int number;
  char *buf, *why;
{
  char name[80], type[100], note[300], *t, mode[8], *tn;
  int flags, size, align, by_value, by_ref, by_descr, out, optional;
  int open, routine;
  struct Node *o;

  flags = p->sdl_flag_bits.flags;
  strcpy(name, str(&p->name));
  if (!name[0]) sprintf(name, "p%d", number);
  oberon_name(name);
  by_value = (flags & SDL$M_VALUE) != 0;
  by_ref = (flags & SDL$M_REF) != 0;
  /* LIB$'s and STR$'s strings carry flag 26 alone: a descriptor */
  by_descr = (flags & (SDL$M_DESCRIPTOR | SDL$M_RTL_STR_DESC)) != 0;
  out = (flags & SDL$M_OUT) != 0;
  optional = (flags & (SDL$M_DEFAULT | SDL$M_OPTIONAL)) != 0;
  open = (flags & (SDL$M_DIMEN | SDL$M_VARDIM)) != 0;
  if (flags & SDL$M_LIST) {
    sprintf(why, "%s is a list", name);
    return 0;
  };
  note[0] = '\0';
  tn = str(&p->typename);
  if (*tn) strcpy(note, tn);
  routine = 0;
  if (p->datatype == SDL$C_TYPE_ENTRY) routine = 1;
  if (p->datatype == SDL$C_TYPE_ADDRESS) {
    o = object(p);
    if (o && o->datatype == SDL$C_TYPE_ENTRY) routine = 1;
  };
  mode[0] = '\0';
  if (routine) {
    /* the argument is the routine's address however SDL marks it */
    strcpy(type, "SYSTEM.ADDRESS");
    by_value = 1;
    if (*note) strcat(note, ", ");
    strcat(note, "a routine's address");
  } else if (by_descr) {
    if (p->datatype == SDL$C_TYPE_CHARACTER) {
      strcpy(type, "ARRAY OF CHAR");
      strcpy(mode, out ? "VAR" : "-");
    } else {
      strcpy(type, "SYSTEM.ADDRESS");
      by_value = 1;
      if (*note) strcat(note, ", ");
      strcat(note, "a descriptor built by hand");
    };
  } else if (by_value) {
    t = scalar_type(p->datatype, &size, &align);
    if (p->datatype == SDL$C_TYPE_ANY) t = "SYSTEM.ADDRESS";
    else if (!t || size > 4) {
      sprintf(why, "%s is wider than a longword by value", name);
      return 0;
    };
    if (p->datatype != SDL$C_TYPE_BOOLEAN && p->datatype != SDL$C_TYPE_ANY)
      t = unsigned_type(t, flags);
    strcpy(type, t);
  } else if (by_ref) {
    strcpy(mode, out ? "VAR" : "-");
    if (p->datatype == SDL$C_TYPE_CHARACTER) {
      /* the characters' address: one, or a length SDL leaves to
         another argument (typeinfo -999, LENGTH *) */
      if (p->typeinfo == 1 && !open) strcpy(type, "CHAR");
      else strcpy(type, "ARRAY OF SYSTEM.BYTE");
    } else {
      t = scalar_type(p->datatype, &size, &align);
      if (p->datatype != SDL$C_TYPE_BOOLEAN) t = unsigned_type(t, flags);
      if (t && p->datatype != SDL$C_TYPE_QUADWORD) {
        if (open) sprintf(type, "ARRAY OF %s", t);
        else strcpy(type, t);
      } else
        strcpy(type, "ARRAY OF SYSTEM.BYTE");
    };
  } else {
    sprintf(why, "%s has no mechanism", name);
    return 0;
  };
  if (p->datatype == SDL$C_TYPE_BOOLEAN) {
    if (*note) strcat(note, ", ");
    strcat(note, "boolean");
  };
  if ((flags & SDL$M_UNSIGNED) && !strstr(type, "CARD")) {
    if (*note) strcat(note, ", ");
    strcat(note, "unsigned");
  };
  if (optional) {
    if (*note) strcat(note, ", ");
    strcat(note, (by_value || routine) ? "optional: 0 omits it"
                                       : "optional: NIL omits it");
  };
  if (p->comment && *comment_text(p->comment)) {
    if (*note) strcat(note, "; ");
    strncat(note, comment_text(p->comment), 120);
  };
  if (strcmp(mode, "VAR") == 0) sprintf(buf, "VAR %s: %s", name, type);
  else if (strcmp(mode, "-") == 0) sprintf(buf, "%s-: %s", name, type);
  else sprintf(buf, "%s: %s", name, type);
  if (*note) {
    strcat(buf, "\001");
    strcat(buf, note);
  };
  return 1;
}

static char *result_type(t)
  int t;
{
  switch (t) {
  case 0: return "";
  case SDL$C_TYPE_LONGWORD: return "SYSTEM.INT32";
  case SDL$C_TYPE_WORD: return "SYSTEM.INT16";
  case SDL$C_TYPE_BYTE: return "SYSTEM.INT8";
  case SDL$C_TYPE_BOOLEAN: return "SYSTEM.INT8";
  case SDL$C_TYPE_ADDRESS: return "SYSTEM.ADDRESS";
  case SDL$C_TYPE_FFLOAT: return "REAL";
  case SDL$C_TYPE_GFLOAT: return "LONGREAL";
  };
  return 0;
}

#define MAXPARAMS 40
static char (*formals)[600]; /* MAXPARAMS of them, from sdl$output */

static void entry(e)
  struct Node *e;
{
  char name[80], why[200], *result, *note, *tn, typename[80];
  struct Node *head, *p;
  int n, i;

  strcpy(name, upper(str(&e->name)));
  enter_section(SECTION_PROCEDURE);
  why[0] = '\0';
  if (e->sdl_flag_bits.flags & SDL$M_VARIABLE)
    strcpy(why, "a variable argument list");
  result = result_type(e->datatype);
  /* a condition value stays SYSTEM.INT32 however SDL marks it; a result
     whose type name says unsigned is the CARD of its width (part 3,
     proposal 3) */
  strncpy(typename, str(&e->typename), sizeof typename - 1);
  typename[sizeof typename - 1] = '\0';
  upper(typename);
  if (result && (strcmp(typename, "LONGWORD_UNSIGNED") == 0
                 || strcmp(typename, "WORD_UNSIGNED") == 0))
    result = unsigned_type(result, SDL$M_UNSIGNED);
  if (!result) sprintf(why, "its result is SDL type %d", e->datatype);
  n = 0;
  head = e->child;
  if (head && !why[0])
    for (p = head->flink; p != head; p = p->flink) {
      if (p->type != SDL$C_NODE_PARAMETER) continue;
      if (n >= MAXPARAMS) {
        strcpy(why, "too many parameters");
        break;
      };
      if (!formal(p, n + 1, formals[n], why)) break;
      n++;
    };
  if (!why[0] && find_name(name) >= 0)
    strcpy(why, "its name is declared already");
  if (why[0]) {
    sprintf(line, "  (* %s left out: %s *)\n", name, why);
    put(&body, line);
    sprintf(line, "%s left out: %s", name, why);
    report(line);
    return;
  };
  add_name(name, 0, 0);
  sprintf(line, "  PROCEDURE [\"VMS\", \"%s\"] %s*(", name, name);
  put(&body, line);
  for (i = 0; i < n; i++) {
    note = strchr(formals[i], '\001');
    if (note) *note++ = '\0';
    sprintf(line, "\n      %s%s", formals[i], i < n - 1 ? ";" : "");
    put(&body, line);
    if (note) {
      sprintf(line, " (* %s *)", note);
      put(&body, line);
    };
  };
  if (n > 0) put(&body, "\n    ");
  put(&body, ")");
  if (*result) {
    sprintf(line, ": %s", result);
    put(&body, line);
  };
  put(&body, ";");
  tn = str(&e->typename);
  if (*tn || e->comment) {
    sprintf(line, " (* %s%s%s *)", tn,
            (*tn && e->comment && *comment_text(e->comment)) ? "; " : "",
            e->comment ? comment_text(e->comment) : "");
    put(&body, line);
  };
  put(&body, "\n");
}

/* ---- modules -------------------------------------------------------- */

static void declarations();

static void declaration(n)
  struct Node *n;
{
  switch (n->type) {
  case SDL$C_NODE_COMMENT:
    add_comment_line(n);
    break;
  case SDL$C_NODE_CONSTANT:
    constant_node(n);
    break;
  case SDL$C_NODE_ITEM:
    if (n->datatype == SDL$C_TYPE_STRUCTURE || n->datatype == SDL$C_TYPE_UNION)
      aggregate(n);
    else {
      enter_section(SECTION_CONST);
      sprintf(line, "    (* item %s left out: not an aggregate *)\n", str(&n->name));
      put(&body, line);
      sprintf(line, "item %s left out: not an aggregate", str(&n->name));
      report(line);
    };
    break;
  case SDL$C_NODE_ENTRY:
    entry(n);
    break;
  case SDL$C_NODE_UNKNOWN:
  case NODE_CONDITIONAL:
    /* a conditional (IFSYMBOL): its typeinfo2 is the condition, its
       child ring the declarations it guards, in STARLET older forms of
       entries ($ADD_BRANCH ...) the main ring declares again; left out */
    break;
  case SDL$C_NODE_HEAD:
    break;
  default:
    sprintf(line, "node type %d left out", n->type);
    report(line);
  };
}

/* each node of the ring with head h */
static void declarations(h)
  struct Node *h;
{
  struct Node *n;

  if (!h) return;
  if (h->type != SDL$C_NODE_HEAD) {
    declaration(h);
    return;
  };
  for (n = h->flink; n != h; n = n->flink) declaration(n);
}

static FILE *outfile;

static void module(m)
  struct Node *m;
{
  char *s, *d, c;
  int i;

  s = str(&m->name);
  if (*s == '$') s++;
  for (d = module_name; *s; s++) *d++ = (*s == '$') ? '_' : toupper(*s);
  *d = '\0';
  for (i = 0; i < nnames; i++) free(names[i].name);
  nnames = 0;
  body.len = 0;
  put(&body, "");
  pending.len = 0;
  put(&pending, "");
  pending_lines = 0;
  section = SECTION_NONE;
  declarations(m->child);
  flush_comments("  ");
  fprintf(outfile, "(*** FILE %s.Mod ***)\n", module_name);
  fprintf(outfile, "MODULE %s;\n\n", module_name);
  fprintf(outfile, "  (* SDL module %s, from %s.\n", str(&m->name), source);
  fprintf(outfile, "     Generated by tools/sdloberon; do not edit. *)\n");
  if (strstr(body.s, "SYSTEM.")) fprintf(outfile, "\n  IMPORT SYSTEM;\n");
  /* a line at a time: VAX C's fputs writes nothing of a string longer
     than 65535 characters (STARLET's body is 190000) */
  for (s = body.s; *s; s = d) {
    d = strchr(s, '\n');
    d = d ? d + 1 : s + strlen(s);
    c = *d;
    *d = '\0';
    fputs(s, outfile);
    *d = c;
  };
  fprintf(outfile, "\nEND %s.\n", module_name);
}

#ifdef vms
static char *get_symbol(name)
  char *name;
{
  static char buf[256];
  short len;
  struct dsc$descriptor_s n, v;
  int status;

  n.dsc$w_length = strlen(name);
  n.dsc$b_dtype = DSC$K_DTYPE_T;
  n.dsc$b_class = DSC$K_CLASS_S;
  n.dsc$a_pointer = name;
  v.dsc$w_length = sizeof buf - 1;
  v.dsc$b_dtype = DSC$K_DTYPE_T;
  v.dsc$b_class = DSC$K_CLASS_S;
  v.dsc$a_pointer = buf;
  len = 0;
  status = lib$get_symbol(&n, &v, &len);
  if (!(status & 1)) len = 0;
  buf[len] = '\0';
  return buf;
}
#else
static char *get_symbol(name)
  char *name;
{
  char *s;

  s = getenv(name);
  return s ? s : "";
}
#endif

sdl$output(outputname, module_node, root)
  struct sptr *outputname, *module_node;
  struct Head *root;
{
  struct Node *r, *m;
  char out[256], version[20];
  int i;

  for (i = 0; i < outputname->len && outputname->str[i] != ' '; i++)
    out[i] = outputname->str[i];
  out[i] = '\0';
  if (i == 0) sprintf(out, "%s.OBN", str(module_node));
#ifdef vms
  outfile = fopen(out, "w", "rfm=var", "rat=cr");
#else
  outfile = fopen(out, "w");
#endif
  if (!outfile) {
    printf("sdloberon: cannot write %s\n", out);
    return 0;
  };
  for (i = 0; i < 10 && root->version[i] && root->version[i] != ' '; i++)
    version[i] = root->version[i];
  version[i] = '\0';
  names = calloc(MAXNAMES, sizeof *names);
  fields = calloc(MAXFIELDS, sizeof *fields);
  copy = calloc(MAXFIELDS, sizeof *copy);
  formals = calloc(MAXPARAMS, sizeof *formals);
  if (!names || !fields || !copy || !formals) {
    printf("sdloberon: out of memory\n");
    return 0;
  };
  strncpy(source, get_symbol("SDLOBERON_SOURCE"), 300);
  source[300] = '\0';
  if (*source) strcat(source, ",\n     ");
  strcat(source, "by SDL ");
  strcat(source, version);
  problems = 0;
  r = root->head;
  for (m = r->flink; m != r && m->type == SDL$C_NODE_MODULE; m = m->flink)
    module(m);
  fclose(outfile);
  printf("sdloberon: %s written, %d problem%s\n", out, problems,
         problems == 1 ? "" : "s");
  return 1;
}
