# awk -f compare-mlb.awk <M>.Mod C_<M>.LIS: the constants of a generated
# module against the global symbols of the listing of $<M> GLOBAL from
# STARLET.MLB, the same SDL as SDL's MACRO back end wrote it. MACRO
# upper-cases a name and keeps 31 characters, so they are compared so;
# a value as a longword. Prints the count of names that agree, and each
# that differs or is on one side only.
function hex(s,    i, n) {
  n = 0
  for (i = 1; i <= length(s); i++) n = n * 16 + index("0123456789ABCDEF", substr(s, i, 1)) - 1
  return n
}
function longword(v) {
  if (v ~ /H$/) { v = substr(v, 1, length(v) - 1); if (length(v) > 8) v = substr(v, length(v) - 7); return hex(v) }
  v = v + 0
  if (v < 0) v += 4294967296
  return v
}
FNR == 1 { file++ }
file == 1 && /^    [A-Za-z0-9_$]+\* = -?[0-9A-F]+H?;/ {
  name = $1; sub(/\*$/, "", name)
  value = $3; sub(/;.*/, "", value)
  key = substr(toupper(name), 1, 31)
  here[key] = longword(value); shown[key] = name
  if (!module) { module = FILENAME; sub(/.*\//, "", module); sub(/\.Mod$/, "", module) }
}
file == 2 {
  line = $0
  while (match(line, /[^ =]+ *= *[0-9A-F]+  G/)) {
    entry = substr(line, RSTART, RLENGTH)
    line = substr(line, RSTART + RLENGTH)
    split(entry, part, /[ =]+/)
    mlb[part[1]] = hex(part[2])
  }
}
END {
  agree = 0
  for (k in here) {
    if (!(k in mlb)) out[++n] = "  only here: " shown[k]
    else if (here[k] != mlb[k]) out[++n] = "  differs: " shown[k] " " here[k] ", STARLET.MLB " mlb[k]
    else agree++
  }
  for (k in mlb) if (!(k in here)) out[++n] = "  only in STARLET.MLB: " k
  # in a fixed order, whatever awk's
  for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++) if (out[j] < out[i]) { t = out[i]; out[i] = out[j]; out[j] = t }
  print module ": " agree " agree"
  for (i = 1; i <= n; i++) print out[i]
}
