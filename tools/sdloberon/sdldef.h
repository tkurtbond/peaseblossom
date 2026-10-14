/* Version 1.0, Feb 4, 1988
   First release - No modifications.

   Standard include file for SDL modules (UNSDL, SDLCC, SDLDUMP)
*/
struct itmlst { /* this is an item list - for getjpi etc. */
  short int  BufLen;
  short int  ItmCod;
  char      *BufAdr;
  short int *RetLenAdr;
};

struct sptr { /* this is a string pointer, as used in PLI apparently */
  short int len;
  char str[32];
};

struct Head {
    char fill[298];
    short int banner_len;
    char banner[68];
    char version[10];
    struct Node *head;
};

struct Node {
  /* this is the structure of a node used in the tree created by
     SDL/NOPARSE, note that I have not been able to find where the
     src_lines variable is kept, since I have not found any SDI
     files that contain a non-zero src_lines field. */
  struct Node *flink, *blink;
  short int size;
  short int type;
  struct Node *parent, *child;
  char fill1[4];
  int hidim;
  int lodim;
  int default_value;
  struct sptr name;
  char fill2[2];
  struct sptr prefix;
  char fill3[34];
  struct sptr tag;
  struct sptr naked;
  char fill4[2];
  int offset;
  int fldsiz;
  unsigned int datatype;
  union {
    int flags;
    struct {
      unsigned m_value : 1;
      unsigned m_mask : 1;
      unsigned m_unsigned : 1;
      unsigned m_common : 1; /* ??? */
      unsigned m_global : 1; /* ??? */
      unsigned m_varying : 1; /* ??? */
      unsigned m_variable : 1;
      unsigned m_based : 1;
      unsigned m_descriptor : 1;
      unsigned m_dimen : 1;
      unsigned m_in : 1;
      unsigned m_out : 1;
      unsigned m_bottom : 1;
      unsigned m_bound : 1; /* ??? */
      unsigned m_ref : 1;
      unsigned m_fill : 1;
      unsigned m_16 : 1;
      unsigned m_default : 1;
      unsigned m_vardim : 1;
      unsigned m_link : 1;
      unsigned m_optional : 1;
      unsigned m_21 : 1;
      unsigned m_fixed : 1;
      unsigned m_generated : 1;
      unsigned m_24 : 1;
      unsigned m_list : 1;
      unsigned m_rtl_str_desc : 1;
      unsigned m_complex : 1;
      unsigned m_28 : 1;
      unsigned m_29 : 1;
      unsigned m_30 : 1;
      unsigned m_31 : 1;
    } flag;
  } sdl_flag_bits ; /* end of variant_union */
  int typeinfo;
  int typeinfo2;
  struct sptr *comment;
  struct sptr typename;
};

#define SDL$C_NODE_ROOT 1
#define SDL$C_NODE_COMMENT 2
#define SDL$C_NODE_CONSTANT 3
#define SDL$C_NODE_ENTRY 4
#define SDL$C_NODE_ITEM 5
#define SDL$C_NODE_MODULE 6
#define SDL$C_NODE_PARAMETER 7
#define SDL$C_NODE_UNKNOWN 8
#define SDL$C_NODE_OBJECT 9
#define SDL$C_NODE_HEAD 10

#define SDL$C_TYPE_ADDRESS 1
#define SDL$C_TYPE_BYTE 2
#define SDL$C_TYPE_CHARACTER 3
#define SDL$C_TYPE_BOOLEAN 4
#define SDL$C_TYPE_DECIMAL 5 /* ??? */
#define SDL$C_TYPE_DFLOAT 6
#define SDL$C_TYPE_FFLOAT 7
#define SDL$C_TYPE_GFLOAT 8
#define SDL$C_TYPE_HFLOAT 9
#define SDL$C_TYPE_LONGWORD 10
#define SDL$C_TYPE_OCTAWORD 11 /* ??? */
#define SDL$C_TYPE_QUADWORD 12
#define SDL$C_TYPE_BITFIELD 13
#define SDL$C_TYPE_WORD 14
#define SDL$C_TYPE_STRUCTURE 15
#define SDL$C_TYPE_UNION 16
#define SDL$C_TYPE_ANY 17
#define SDL$C_TYPE_ENTRY 18
#define SDL$C_TYPE_DFLOAT_COMPLEX 19
#define SDL$C_TYPE_FFLOAT_COMPLEX 20
#define SDL$C_TYPE_GFLOAT_COMPLEX 21
#define SDL$C_TYPE_HFLOAT_COMPLEX 22 /* guess */

#define SDL$M_VALUE 1<<0
#define SDL$M_MASK 1<<1
#define SDL$M_UNSIGNED 1<<2
#define SDL$M_COMMON 1<<3 /* ??? */
#define SDL$M_GLOBAL 1<<4 /* ??? */
#define SDL$M_VARYING 1<<5 /* ??? */
#define SDL$M_VARIABLE 1<<6
#define SDL$M_BASED 1<<7
#define SDL$M_DESCRIPTOR 1<<8
#define SDL$M_DIMEN 1<<9
#define SDL$M_IN 1<<10
#define SDL$M_OUT 1<<11
#define SDL$M_BOTTOM 1<<12
#define SDL$M_BOUND 1<<13 /* ?? */
#define SDL$M_REF 1<<14
#define SDL$M_FILL 1<<15
#define SDL$M_16 1<<16 /* ??? */
#define SDL$M_DEFAULT 1<<17
#define SDL$M_VARDIM 1<<18
#define SDL$M_LINK 1<<19
#define SDL$M_OPTIONAL 1<<20
#define SDL$M_21 1<<21 /* ??? */
#define SDL$M_FIXED 1<<22
#define SDL$M_GENERATED 1<<23
#define SDL$M_24 1<<24
#define SDL$M_LIST 1<<25
#define SDL$M_RTL_STR_DESC 1<<26
#define SDL$M_COMPLEX 1<<27
#define SDL$M_28 1<<28
#define SDL$M_29 1<<29
#define SDL$M_30 1<<30
#define SDL$M_31 1<<31

#define SDL_SYMBOL "SDL_COMMAND_ARGS"
