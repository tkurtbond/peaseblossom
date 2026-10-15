# Writes VmsDefLayout.mod, which checks poc's layout of every record type
# in the generated modules named on the command line against SDL's
# offsets: each exported field's offset, SYSTEM.ADR(v.f) - SYSTEM.ADR(v),
# against the module's constant of the field's name, and the record's
# size against its comment, "(* n bytes" or "which poc pads to n". An
# aggregate with an ORIGIN says so there, "ORIGIN, n bytes in", and its
# constants count from it. A field of bit fields has a $V_ constant, a
# bit's position, not an offset, and is left out.
FNR == 1 {
  module = FILENAME; sub(/.*\//, "", module); sub(/\.Mod$/, "", module)
  inrecord = 0
}
/^    [A-Za-z0-9_$]+\* = [-0-9A-F]+H?;/ {
  name = $1; sub(/\*$/, "", name); constant[module "." name] = 1
}
/^    [A-Za-z0-9_$]+\* = RECORD \(\* [0-9]+ bytes/ {
  type = $1; sub(/\*$/, "", type)
  size = $5
  if (match($0, /pads to [0-9]+/)) size = substr($0, RSTART + 8, RLENGTH - 8)
  origin = 0
  if (match($0, /ORIGIN, [0-9]+ bytes in/)) origin = substr($0, RSTART + 8, RLENGTH - 17)
  nrecords++; rmodule[nrecords] = module; rtype[nrecords] = type; rsize[nrecords] = size
  rorigin[nrecords] = origin
  nfields[nrecords] = 0; inrecord = 1; used[module] = 1
  next
}
inrecord && /^    END;/ { inrecord = 0; next }
inrecord && /^      [A-Za-z0-9_$]+\*:/ {
  if ($0 ~ /\(\* bit fields \*\)/) { skipped++; next }
  f = $1; sub(/\*:$/, "", f)
  n = ++nfields[nrecords]; field[nrecords, n] = f
}
END {
  print "MODULE VmsDefLayout;"
  print "  (* written by layout-check.awk: poc's layout of each record type"
  print "     of rtl/vax/vms against SDL's offsets and sizes *)"
  imports = "SYSTEM, Out"
  for (m in used) list[++nused] = m
  # in a fixed order, whatever awk's
  for (i = 1; i <= nused; i++) for (j = i + 1; j <= nused; j++)
    if (list[j] < list[i]) { t = list[i]; list[i] = list[j]; list[j] = t }
  for (i = 1; i <= nused; i++) imports = imports ", " list[i]
  print "  IMPORT " imports ";"
  print "  VAR errors: INTEGER;"
  for (r = 1; r <= nrecords; r++)
    print "    v" r ": " rmodule[r] "." rtype[r] ";"
  print ""
  print "  PROCEDURE Check(name: ARRAY OF CHAR; offset, expected: LONGINT);"
  print "  BEGIN"
  print "    IF offset # expected THEN"
  print "      Out.String(name); Out.String(\" at \"); Out.Int(offset, 0);"
  print "      Out.String(\", not \"); Out.Int(expected, 0); Out.Ln; INC(errors)"
  print "    END"
  print "  END Check;"
  print ""
  print "  PROCEDURE Record(name: ARRAY OF CHAR; fields, size, expected: LONGINT);"
  print "  BEGIN"
  print "    Out.String(name); Out.String(\": \"); Out.Int(fields, 0); Out.String(\" fields, \");"
  print "    Out.Int(size, 0); Out.String(\" bytes\");"
  print "    IF size # expected THEN Out.String(\", not \"); Out.Int(expected, 0); INC(errors) END;"
  print "    Out.Ln"
  print "  END Record;"
  print ""
  print "BEGIN"
  for (r = 1; r <= nrecords; r++) {
    checked = 0
    for (i = 1; i <= nfields[r]; i++) {
      f = field[r, i]
      if (!((rmodule[r] "." f) in constant)) continue
      checked++
      if (rorigin[r])
        printf "  Check(\"%s.%s\", SYSTEM.ADR(v%d.%s) - SYSTEM.ADR(v%d) - %d, %s.%s);\n", rmodule[r], f, r, f, r, rorigin[r], rmodule[r], f
      else
        printf "  Check(\"%s.%s\", SYSTEM.ADR(v%d.%s) - SYSTEM.ADR(v%d), %s.%s);\n", rmodule[r], f, r, f, r, rmodule[r], f
    }
    printf "  Record(\"%s.%s\", %d, SIZE(%s.%s), %d);\n", rmodule[r], rtype[r], checked, rmodule[r], rtype[r], rsize[r]
  }
  print "  Out.Int(errors, 0); Out.String(\" layout errors\"); Out.Ln"
  print "END VmsDefLayout."
}
