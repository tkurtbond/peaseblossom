/* Version 1.0 (Hmm, should be 0.something) Feb. 4, 1988
   First release - no modifications

   This program does a dump of the internal tree created by SDL/NOPARSE.
   This dump doesn't look like the dump from SDL/NOPARSE/DUMP, although
   it probably should so that we could use DIFFERENCES to see if I have
   all the datatypes and structures and such figured out correctly.

   Note that there should be some modifications - I just added
   code to UNSDL (actually, I just created it) and to SDLCC to allow
   passing extra information than was allowed via the SDL command.
   The code from SDLCC should be brought into this module
   at some point.
*/
#include <stdio.h>
#include "sdldef.h"

int readable();

sdl$output(outfile, module, root)
  struct sptr *outfile, *module;
  struct Head *root;

{
  struct Node *node;
  char out[256];
  int i;

  /* get outfile copied into local space, so I can add a zero to it. */
  for (i=0; (i < outfile->len) & (outfile->str[i] != ' '); i++)
    out[i] = outfile->str[i];
  out[i] = '\0';
  /* if no output file name present, use module name. */
  if (i==0) {
    for (i=0; (i < module->len) & (module->str[i] != ' '); i++)
      out[i] = module->str[i];
    out[i] = '.';
    out[i+1] = 'd';
    out[i+2] = 'm';
    out[i+3] = 'p';
    out[i+4] = '\0';
  };
  freopen(out,"w",stdout,"rfm=var","rat=cr");

  printf("Created by SDL %.*s\n",10,root->version);
  printf("Source: %.*s\n",root->banner_len,root->banner);
  printf("Module name is %.*s\n",module->len,&(module->str));

  node = root->head;
  traverse_node(node,0); /* this should be the root node */
}

traverse_node(node,level)
  struct Node *node;
  int level;
{
  struct Node *head;

  head = node;
  if (!readable(node))
    printf("WARNING unable to read address %08X\n",node);
  else
    do {
      print_node(node,level);
      printf("\n");

      if ((node->datatype == 1) && node->typeinfo2)  /* address */
        traverse_node(node->typeinfo2,level+1);

      if ((node->datatype == 18) && node->typeinfo2) /* entry */
        traverse_node(node->typeinfo2,level+1);

      if (node->child)
        traverse_node(node->child,level+1);

      node = node->flink;

      if (!readable(node)) {
        printf("WARNING unable to read address %08X\n",node);
        node = head; /* cause it to fall out of loop */
      };

    } while (node != head);
}

print_node(node,level)
  struct Node *node;
  int level;
{
  struct sptr *ptr;
  int i;

  static char *unknown = "unknown";

  static char *nodetypes[11] = {"?","root","comment","constant","entry","item",
	"module","parameter","?","object","head"};

  static char *datatypes[19] = {"?","address","byte","character","boolean",
	"decimal?","d-float","f-float","g-float","h-float","longword",
	"octaword?","quadword","bitfield","word","structure",
	"union","any","entry"};

  static char *flags[24] = {"value","mask","unsigned","common3?","global4?",
	"varying5?","variable","based","descriptor","dimen","in",
	"out","bottom","bound13?","ref","fill","16?","default",
	"vardim","link","optional","21?","fixed","generated"};
  static char spaces[] = "                                             ";

  if (level > 15) level = 15;

  printf("%.*sAddress: %08X Type: %s node\n",level*3,spaces,
		node,((node->type > 0) && (node->type < 11))?
			nodetypes[node->type]:unknown);

  printf("%.*sFlink: %08X, Blink: %08X\n",level*3,spaces,
		node->flink,node->blink);
  printf("%.*sParent: %08X, Child: %08X\n",level*3,spaces,
		node->parent,node->child);

  if (node->name.len)
	printf("%.*sName: %.*s\n",level*3,spaces,
		node->name.len,node->name.str);
  if (node->prefix.len)
	printf("%.*sPrefix: %.*s\n",level*3,spaces,
		node->prefix.len,node->prefix.str);
  if (node->tag.len)
	printf("%.*sTag: %.*s\n",level*3,spaces,
		node->tag.len,node->tag.str);
  if (node->naked.len)
	printf("%.*sNaked: %.*s\n",level*3,spaces,
		node->naked.len,node->naked.str);
  if (node->typename.len)
	printf("%.*sTypename: %.*s\n",level*3,spaces,
		node->typename.len,node->typename.str);
  if (node->comment) {
	ptr = node->comment;
	printf("%.*sComment: %.*s\n",level*3,spaces,
		(*ptr).len,(*ptr).str);
	};
  if (node->size) printf("%.*ssize: %d\n",level*3,spaces,node->size);
  /*
   *    if (node->src_line) printf("\tsrc_line %d\n",node->src_line);
   */
  if (node->hidim) printf("%.*shidim: %d\n",level*3,spaces,node->hidim);
  if (node->lodim) printf("%.*slodim: %d\n",level*3,spaces,node->lodim);
  if (node->offset) printf("%.*soffset: %d\n",level*3,spaces,node->offset);
  if (node->fldsiz) printf("%.*sfldsiz: %d\n",level*3,spaces,node->fldsiz);

  if (node->datatype)
    printf("%.*sdatatype: %s (%d)\n",level*3,spaces,
		(node->datatype < 19)?
			datatypes[node->datatype]:unknown, node->datatype);

  if (node->sdl_flag_bits.flags)
	if (!((node->type == 4) && (node->sdl_flag_bits.flags == 0x00010000))) {
		printf("%.*sflags: (%08X) ",
			level*3,spaces,node->sdl_flag_bits.flags);
  		for (i=0; i<24; i++)
		  if (node->sdl_flag_bits.flags & (1<<i))
		    printf("%s ",flags[i]);
  		for (i=24; i<32; i++)
		  if (node->sdl_flag_bits.flags & (1<<i))
		    printf("%d? ",i);
		printf("\n");
		};

  if (node->typeinfo)
    printf("%.*stypeinfo: %08X (%d)\n",level*3,spaces,
		node->typeinfo,node->typeinfo);
  if (node->typeinfo2)
    printf("%.*stypeinfo2: %08X (%d)\n",level*3,spaces,
		node->typeinfo2,node->typeinfo2);
  if (node->default_value)
    printf("%.*sdefault_value: %08X (%d)\n",level*3,spaces,
		node->default_value,node->default_value);

  for (i=0;i<4;i++)
    if (node->fill1[i]) {
      printf("%.*s*** fill1[] ",level*3,spaces);
      for (i=3; i >= 0;i--)
        printf("%02x",node->fill1[i]);
      printf("\n");
      i = 5;
      };
  for (i=0;i<2;i++)
    if (node->fill2[i]) {
      printf("%.*s*** fill2[] ",level*3,spaces);
      for (i=1; i >= 0;i--)
        printf("%02x",node->fill2[i]);
      printf("\n");
      i = 3;
      };
  for (i=0;i<34;i++)
    if (node->fill3[i]) {
      printf("%.*s*** fill3[] ",level*3,spaces);
      for (i=33; i >= 0;i--)
        printf("%02x",node->fill3[i]);
      printf("\n");              
      i = 35;
      };
  for (i=0;i<2;i++)
    if (node->fill4[i]) {
      printf("%.*s*** fill4[] ",level*3,spaces);
      for (i=1; i >= 0;i--)
        printf("%02x",node->fill4[i]);
      printf("\n");
      };
}
