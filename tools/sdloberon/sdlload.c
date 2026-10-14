/* sdlload.c - runs sdloberon.c's sdl$output on atla, over a tree read
   back from SDLDUMP's dump of it (sdldump.c), so that the back end can be
   tried before it goes to the guest.

     cc -m32 -std=gnu89 -o sdlload sdlload.c sdloberon.c
     ./sdlload <dump>.DMP <output>

   The dump prints each node's own address and its links, so the tree is
   rebuilt as SDLNPARSE made it, with 32-bit pointers (-m32) where
   sdldef.h keeps one in an int. */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "sdldef.h"

int sdl$output();

#define MAXNODES 200000

static struct {
  unsigned address;
  struct Node *node;
  unsigned flink, blink, parent, child, typeinfo2;
} nodes[MAXNODES];
static int nnodes;

static int by_address(a, b)
  const void *a, *b;
{
  unsigned x, y;

  x = ((const unsigned *)a)[0];
  y = ((const unsigned *)b)[0];
  return x < y ? -1 : x > y;
}

/* the node at address, once nodes is sorted by address */
static struct Node *find(address)
  unsigned address;
{
  int lo, hi, mid;

  lo = 0;
  hi = nnodes - 1;
  while (lo <= hi) {
    mid = (lo + hi) / 2;
    if (nodes[mid].address == address) return nodes[mid].node;
    if (nodes[mid].address < address) lo = mid + 1;
    else hi = mid - 1;
  }
  return 0;
}

static void set_sptr(p, s)
  struct sptr *p;
  char *s;
{
  int n;

  n = strlen(s);
  if (n > 32) n = 32;
  p->len = n;
  memcpy(p->str, s, n);
}

static char *types[] = {"?", "root", "comment", "constant", "entry", "item",
  "module", "parameter", "unknown", "object", "head", 0};

int main(argc, argv)
  int argc;
  char **argv;
{
  FILE *f;
  char text[4096], *s, *v;
  struct Node *n;
  struct Head head;
  struct sptr out, module;
  int i, k;

  if (argc != 3) {
    fprintf(stderr, "usage: sdlload <dump> <output>\n");
    return 2;
  }
  f = fopen(argv[1], "r");
  if (!f) {
    perror(argv[1]);
    return 2;
  }
  memset(&head, 0, sizeof head);
  n = 0;
  while (fgets(text, sizeof text, f)) {
    text[strcspn(text, "\r\n")] = '\0';
    for (s = text; *s == ' '; s++);
    if (strncmp(s, "Created by SDL ", 15) == 0) {
      strncpy(head.version, s + 15, 10);
      continue;
    }
    if (strncmp(s, "Source: ", 8) == 0 && nnodes == 0) {
      head.banner_len = strlen(s + 8);
      if (head.banner_len > 68) head.banner_len = 68;
      memcpy(head.banner, s + 8, head.banner_len);
      continue;
    }
    if (strncmp(s, "Address: ", 9) == 0) {
      n = calloc(1, sizeof *n);
      nodes[nnodes].node = n;
      sscanf(s + 9, "%x", &nodes[nnodes].address);
      v = strstr(s, "Type: ") + 6;
      n->type = 8;
      for (k = 1; types[k]; k++)
        if (strncmp(v, types[k], strlen(types[k])) == 0 && v[strlen(types[k])] == ' ')
          n->type = k;
      nnodes++;
      continue;
    }
    if (!n) continue;
    i = nnodes - 1;
    v = strstr(s, ": ");
    if (!v) continue;
    v += 2;
    if (strncmp(s, "Flink:", 6) == 0)
      sscanf(s, "Flink: %x, Blink: %x", &nodes[i].flink, &nodes[i].blink);
    else if (strncmp(s, "Parent:", 7) == 0)
      sscanf(s, "Parent: %x, Child: %x", &nodes[i].parent, &nodes[i].child);
    else if (strncmp(s, "Name:", 5) == 0) set_sptr(&n->name, v);
    else if (strncmp(s, "Prefix:", 7) == 0) set_sptr(&n->prefix, v);
    else if (strncmp(s, "Tag:", 4) == 0) set_sptr(&n->tag, v);
    else if (strncmp(s, "Naked:", 6) == 0) set_sptr(&n->naked, v);
    else if (strncmp(s, "Typename:", 9) == 0) set_sptr(&n->typename, v);
    else if (strncmp(s, "Comment:", 8) == 0) {
      v = s + 8;
      if (*v == ' ') v++;
      n->comment = malloc(sizeof(struct sptr) + strlen(v));
      n->comment->len = strlen(v);
      memcpy(n->comment->str, v, strlen(v));
    } else if (strncmp(s, "size:", 5) == 0) n->size = atoi(v);
    else if (strncmp(s, "hidim:", 6) == 0) n->hidim = atoi(v);
    else if (strncmp(s, "lodim:", 6) == 0) n->lodim = atoi(v);
    else if (strncmp(s, "offset:", 7) == 0) n->offset = atoi(v);
    else if (strncmp(s, "fldsiz:", 7) == 0) n->fldsiz = atoi(v);
    else if (strncmp(s, "datatype:", 9) == 0) n->datatype = atoi(strchr(v, '(') + 1);
    else if (strncmp(s, "flags:", 6) == 0) sscanf(v, "(%x)", (unsigned *)&n->sdl_flag_bits.flags);
    else if (strncmp(s, "typeinfo:", 9) == 0) sscanf(v, "%x", (unsigned *)&n->typeinfo);
    else if (strncmp(s, "typeinfo2:", 10) == 0) sscanf(v, "%x", &nodes[i].typeinfo2);
    else if (strncmp(s, "default_value:", 14) == 0) sscanf(v, "%x", (unsigned *)&n->default_value);
  }
  fclose(f);
  if (nnodes == 0) return 2;
  head.head = nodes[0].node;
  qsort(nodes, nnodes, sizeof nodes[0], by_address);
  for (i = 0; i < nnodes; i++) {
    n = nodes[i].node;
    n->flink = find(nodes[i].flink);
    n->blink = find(nodes[i].blink);
    n->parent = find(nodes[i].parent);
    n->child = find(nodes[i].child);
    if (nodes[i].typeinfo2) {
      if (n->datatype == SDL$C_TYPE_ADDRESS || n->datatype == SDL$C_TYPE_ENTRY
          || n->type == SDL$C_NODE_UNKNOWN)
        n->typeinfo2 = (int)find(nodes[i].typeinfo2);
      else
        n->typeinfo2 = (int)nodes[i].typeinfo2;
    }
  }
  set_sptr(&out, argv[2]);
  set_sptr(&module, "MODULE");
  sdl$output(&out, &module, &head);
  return 0;
}
