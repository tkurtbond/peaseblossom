$ ! Written by poc for VaxBuildSums.mod: assembles its modules
$ ! (doc/developer/vax-macro32-backend.md, section 13). Run it where
$ ! the modules' .MAR files are.
$ ON WARNING THEN EXIT $STATUS
$ MACRO/OBJECT VAXBUILDSUMS.MAR
$ EXIT $STATUS
