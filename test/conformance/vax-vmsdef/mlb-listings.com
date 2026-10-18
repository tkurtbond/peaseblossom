$ ! Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 2,
$ ! proposal 8): each C_<M>.MAR, $<M> GLOBAL from STARLET.MLB, assembled
$ ! with a listing, C_<M>.LIS, whose symbol table compare-mlb.awk reads
$ SET NOON
$ S = 1
$ LOOP:
$ F = F$SEARCH("C_*.MAR")
$ IF F .EQS. "" THEN GOTO DONE
$ N = F$PARSE(F,,,"NAME")
$ MACRO/LIST/NOOBJECT 'N'
$ IF .NOT. $STATUS THEN S = $STATUS
$ DELETE/NOLOG 'N'.MAR;*
$ GOTO LOOP
$ DONE:
$ EXIT S
