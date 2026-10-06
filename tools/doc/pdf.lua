-- A pandoc filter for the PDFs make doc writes (with pdf-header.tex).
--
-- Tables: the GFM reader gives a pipe table's columns no widths, and LaTeX
-- then sets each cell on one line: the Reference Guide's tables ran up to
-- 20 inches off the page. A table whose longest row is wider than the page
-- (72 characters, pandoc's --columns) gives each column its longest word
-- (and at least a tenth of the page), then shares what is left of the page
-- in proportion to how much more each column's longest cell needs, so
-- that its cells wrap.
--
-- Inline code: a long path (src/back/llvm/LLVMCodeGenerator.Mod)
-- or name (MayBeReassignedElsewhere) cannot be hyphenated and ran into the
-- margin. It may now break after a slash, a full stop or an underscore, and
-- between a lower-case letter and a capital; and a slash in the text
-- may break as well.
--
-- Code blocks: a line can be 167 characters long, and verbatim text does
-- not wrap. Each block becomes fancyvrb's Verbatim, in \small, and a line
-- longer than code_width (what fits the text width at that size) is broken
-- at its last blank that fits, or at code_width when none does; the rest
-- is indented as the line was, plus two, after a hooked arrow. Done here
-- rather than with fvextra's breaklines, which not every TeX Live install
-- has.

local text_width = 72
local code_width = 84

local function cell_length(cell)
  return utf8.len(pandoc.utils.stringify(cell.contents)) or 0
end

local function longest_word(cell)
  local n = 0
  for word in pandoc.utils.stringify(cell.contents):gmatch("%S+") do
    n = math.max(n, utf8.len(word) or #word)
  end
  return n
end

local function widen(longest, words, row)
  for i, cell in ipairs(row.cells) do
    longest[i] = math.max(longest[i] or 0, cell_length(cell))
    words[i] = math.max(words[i] or 0, longest_word(cell))
  end
end

function Table(tbl)
  local longest, words = {}, {}
  for _, row in ipairs(tbl.head.rows) do widen(longest, words, row) end
  for _, body in ipairs(tbl.bodies) do
    for _, row in ipairs(body.body) do widen(longest, words, row) end
  end
  local total = 0
  for _, n in ipairs(longest) do total = total + n end
  if total <= text_width then return nil end
  -- each column its least width, then what is left in proportion to how
  -- much more its longest cell needs
  local least, base, more = {}, 0, 0
  for i, n in ipairs(longest) do
    least[i] = math.max(words[i] + 2, text_width / 10)
    base = base + least[i]
    more = more + math.max(n - least[i], 0)
  end
  local spare = math.max(text_width - base, 0)
  local width, sum = {}, 0
  for i, n in ipairs(longest) do
    width[i] = least[i]
    if more > 0 then width[i] = width[i] + spare * math.max(n - least[i], 0) / more end
    sum = sum + width[i]
  end
  for i, spec in ipairs(tbl.colspecs) do
    tbl.colspecs[i] = {spec[1], width[i] / sum}
  end
  return tbl
end

-- the first n characters (not bytes) of s, and the rest
local function split_at(s, n)
  local byte = utf8.offset(s, n + 1)
  if byte == nil then return s, "" end
  return s:sub(1, byte - 1), s:sub(byte)
end

local function break_line(line, out)
  local indent = line:match("^ *") .. "  "
  while (utf8.len(line) or #line) > code_width do
    local head, tail = split_at(line, code_width)
    local blank = head:match("^.*() ")
    if blank ~= nil and blank > #indent + 2 then
      head, tail = line:sub(1, blank - 1), line:sub(blank + 1)
    end
    table.insert(out, head)
    line = indent .. "↪ " .. tail
  end
  table.insert(out, line)
end

function CodeBlock(block)
  local out = {}
  for line in (block.text .. "\n"):gmatch("(.-)\n") do
    break_line(line, out)
  end
  return pandoc.RawBlock("latex",
    "\\begin{Verbatim}[fontsize=\\small]\n" .. table.concat(out, "\n") ..
    "\n\\end{Verbatim}")
end

function Code(code)
  local pieces, start, text = {}, 1, code.text
  for i = 1, #text - 1 do
    local c, d = text:sub(i, i), text:sub(i + 1, i + 1)
    if c:match("[/._]") or (c:match("%l") and d:match("%u")) then
      table.insert(pieces, pandoc.Code(text:sub(start, i)))
      table.insert(pieces, pandoc.RawInline("latex", "\\allowbreak{}"))
      start = i + 1
    end
  end
  if start == 1 then return nil end
  table.insert(pieces, pandoc.Code(text:sub(start)))
  return pieces
end

-- a slash in the text (`SHORTINT`/`INTEGER`/`LONGINT`) may break too
function Str(str)
  if not str.text:find("/", 1, true) then return nil end
  local pieces = {}
  for piece in str.text:gmatch("[^/]*/?") do
    if piece ~= "" then
      table.insert(pieces, pandoc.Str(piece))
      if piece:sub(-1) == "/" then table.insert(pieces, pandoc.RawInline("latex", "\\allowbreak{}")) end
    end
  end
  return pieces
end
