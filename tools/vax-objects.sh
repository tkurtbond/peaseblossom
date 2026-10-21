# '.' this file from tools/vax-guest-poc and tools/bootstrap/vax-stages,
# which compare the objects poc writes on the VAX/VMS guest with those the
# host's poc writes for it (PLAN.md Phase 18 steps 6e and 7;
# doc/developer/vax-object-language.md, sections 17.7 and 18):
#
#   counted_records <file>   the records of an object in poc's counted form
#   dumped_records <file>    the records of an object as DUMP/RECORDS
#                            printed it on the guest
#   without_conversions      a procedure, standard input to standard output,
#                            without the lines that convert objects sent in
#                            binary, which poc writes only off VMS
#
# The awk programs use gawk's strtonum, as on atla, the host that reaches
# the guest.

# An object's records, a line each, its bytes in hexadecimal, from poc's
# counted form (a 2-byte little-endian count, the bytes, a pad byte when the
# count is odd: doc/developer/vax-object-language.md, section 10) or from
# what DUMP/RECORDS printed on the guest: each line's longwords, right to
# left, then the bytes as text and their offset. The source file record
# (SRC, 00 02 and the name as given or found) is the name alone, lowercase,
# without its directory, which differs by system.
counted_records() {
  od -An -v -t x1 "$1" | awk '
    { for (i = 1; i <= NF; i++) byte[n++] = $i }
    END {
      p = 0
      while (p + 1 < n) {
        count = strtonum("0x" byte[p + 1] byte[p]); p += 2; line = ""
        for (i = 0; i < count; i++) line = line byte[p + i]
        print line; p += count + count % 2
      }
    }' | src_record
}
dumped_records() {
  LC_ALL=C awk '
    /^Record number / { if (started) print line; started = 1; line = ""; next }
    started && /^ / {
      hex = substr($0, 1, 72); gsub(/ /, "", hex)
      for (i = length(hex) - 1; i >= 1; i -= 2) line = line tolower(substr(hex, i, 2))
    }
    END { if (started) print line }' "$1" | src_record
}
src_record() {
  LC_ALL=C awk '
    /^0002/ {
      name = ""
      for (i = 5; i < length($0); i += 2) name = name sprintf("%c", strtonum("0x" substr($0, i, 2)))
      sub(/^.*[]\/:>]/, "", name); print "SRC " tolower(name); next
    }
    { print }'
}

# A procedure without its conversion lines and the comment that tells of
# them, which poc writes only off VMS, for objects sent in binary
without_conversions() {
  awk '
    /^\$ ! An object sent in binary from Linux or a BSD/ || /^\$ ! is converted first, by OBJCONVERT/ { next }
    /^\$ IF F\$FILE_ATTRIBUTES\(".*\.OBJ", "RFM"\) \.NES\. "FIX" THEN GOTO CONVERTED_[0-9]+$/ { skip = 3; next }
    skip > 0 { skip--; next }
    { print }'
}
