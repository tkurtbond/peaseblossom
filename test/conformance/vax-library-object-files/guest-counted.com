$ ! vax-library-object-files (doc/developer/vax-macro32-backend.md, section
$ ! 13.1, proposal 6): HAND-TWICE.MAR assembled by MACRO and its object
$ ! written in the counted form by OBJCONVERT -COUNTED, as TWICE.CNT, which
$ ! tools/vax-do brings back in binary. HELPER.OBJ, which tools/vax-do
$ ! sent, made OBJCONVERT ready.
$ SET NOON
$ OBJCONVERT := $'F$PARSE("[.BIN]OBJCONVERT.EXE")'
$ MACRO/OBJECT=TWICE.OBJ HAND-TWICE.MAR
$ S = $STATUS
$ IF S THEN OBJCONVERT "-counted" TWICE.OBJ TWICE.CNT
$ IF S THEN S = $STATUS
$ DELETE/NOLOG TWICE.OBJ;*, HELPER.OBJ;*
$ EXIT S
