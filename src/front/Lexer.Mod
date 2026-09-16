MODULE Lexer;

  (* Lexical scanner for Oberon-2 vocabulary (Oberon2.pdf, Chapter 3).
     Backend- and host-agnostic: operates on an in-memory character
     buffer supplied by the caller and never touches files itself.

     Token.lexeme keeps the exact source text of the token (including
     any H/X suffix on numbers, but excluding the surrounding quotes on
     strings); numeric value computation is deferred to a later phase
     (PLAN.md Phase 3, ConstantEvaluator.Mod). *)

  IMPORT Diagnostics;

  CONST
    maxLexemeLength = 255;

    (* Token kinds *)
    eof* = 0;
    ident* = 1;
    integer* = 2;
    real* = 3;
    charConst* = 4;
    string* = 5;
    invalid* = 6;

    plus* = 7; minus* = 8; times* = 9; slash* = 10; tilde* = 11;
    ampersand* = 12; period* = 13; comma* = 14; semicolon* = 15;
    verticalBar* = 16; leftParen* = 17; rightParen* = 18;
    leftBracket* = 19; rightBracket* = 20; leftBrace* = 21; rightBrace* = 22;
    assign* = 23; caret* = 24; equal* = 25; notEqual* = 26;
    less* = 27; greater* = 28; lessEqual* = 29; greaterEqual* = 30;
    upTo* = 31; colon* = 32;

    arrayKeyword* = 33; beginKeyword* = 34; byKeyword* = 35; caseKeyword* = 36;
    constKeyword* = 37; divKeyword* = 38; doKeyword* = 39; elseKeyword* = 40;
    elsifKeyword* = 41; endKeyword* = 42; exitKeyword* = 43; forKeyword* = 44;
    ifKeyword* = 45; importKeyword* = 46; inKeyword* = 47; isKeyword* = 48;
    loopKeyword* = 49; modKeyword* = 50; moduleKeyword* = 51; nilKeyword* = 52;
    ofKeyword* = 53; orKeyword* = 54; pointerKeyword* = 55; procedureKeyword* = 56;
    recordKeyword* = 57; repeatKeyword* = 58; returnKeyword* = 59; thenKeyword* = 60;
    toKeyword* = 61; typeKeyword* = 62; untilKeyword* = 63; varKeyword* = 64;
    whileKeyword* = 65; withKeyword* = 66;

  TYPE
    CharBuffer* = POINTER TO ARRAY OF CHAR;

    Token* = RECORD
      kind*: INTEGER;
      line*, column*: INTEGER;
      lexeme*: ARRAY maxLexemeLength + 1 OF CHAR;
      isHex*: BOOLEAN;       (* integer literal used the H suffix *)
      isLongReal*: BOOLEAN   (* real literal had a D scale factor *)
    END;

    Scanner* = RECORD
      text: CharBuffer;
      length: LONGINT;
      pos: LONGINT;
      line, column: INTEGER
    END;

  PROCEDURE IsLetter(ch: CHAR): BOOLEAN;
  BEGIN
    RETURN ((ch >= "a") & (ch <= "z")) OR ((ch >= "A") & (ch <= "Z"))
  END IsLetter;

  PROCEDURE IsDigit(ch: CHAR): BOOLEAN;
  BEGIN
    RETURN (ch >= "0") & (ch <= "9")
  END IsDigit;

  PROCEDURE IsHexDigit(ch: CHAR): BOOLEAN;
  BEGIN
    RETURN IsDigit(ch) OR ((ch >= "A") & (ch <= "F"))
  END IsHexDigit;

  PROCEDURE CurrentChar(VAR s: Scanner): CHAR;
  BEGIN
    IF s.pos < s.length THEN RETURN s.text[s.pos] ELSE RETURN 0X END
  END CurrentChar;

  PROCEDURE PeekChar(VAR s: Scanner; offset: LONGINT): CHAR;
    VAR p: LONGINT;
  BEGIN
    p := s.pos + offset;
    IF p < s.length THEN RETURN s.text[p] ELSE RETURN 0X END
  END PeekChar;

  PROCEDURE Advance(VAR s: Scanner);
    (* s.column always names the column of the not-yet-consumed character
       at s.text[s.pos], so a token's start column can simply be read as
       s.column before scanning it. *)
    VAR c: CHAR;
  BEGIN
    IF s.pos < s.length THEN
      c := s.text[s.pos];
      INC(s.pos);
      IF c = 0AX THEN
        INC(s.line); s.column := 1
      ELSE
        INC(s.column)
      END
    END
  END Advance;

  PROCEDURE SkipWhiteSpaceAndComments(VAR s: Scanner);
    VAR depth: INTEGER; startLine, startColumn: INTEGER; ch: CHAR;
  BEGIN
    LOOP
      ch := CurrentChar(s);
      WHILE (ch = " ") OR (ch = 9X) OR (ch = 0DX) OR (ch = 0AX) DO
        Advance(s); ch := CurrentChar(s)
      END;
      IF (ch = "(") & (PeekChar(s, 1) = "*") THEN
        startLine := s.line; startColumn := s.column;
        Advance(s); Advance(s);
        depth := 1;
        WHILE depth > 0 DO
          ch := CurrentChar(s);
          IF ch = 0X THEN
            Diagnostics.Error(startLine, startColumn, "unterminated comment");
            depth := 0
          ELSIF (ch = "(") & (PeekChar(s, 1) = "*") THEN
            Advance(s); Advance(s); INC(depth)
          ELSIF (ch = "*") & (PeekChar(s, 1) = ")") THEN
            Advance(s); Advance(s); DEC(depth)
          ELSE
            Advance(s)
          END
        END
      ELSE
        EXIT
      END
    END
  END SkipWhiteSpaceAndComments;

  PROCEDURE LookupKeyword(name: ARRAY OF CHAR): INTEGER;
  BEGIN
    IF name = "ARRAY" THEN RETURN arrayKeyword
    ELSIF name = "BEGIN" THEN RETURN beginKeyword
    ELSIF name = "BY" THEN RETURN byKeyword
    ELSIF name = "CASE" THEN RETURN caseKeyword
    ELSIF name = "CONST" THEN RETURN constKeyword
    ELSIF name = "DIV" THEN RETURN divKeyword
    ELSIF name = "DO" THEN RETURN doKeyword
    ELSIF name = "ELSE" THEN RETURN elseKeyword
    ELSIF name = "ELSIF" THEN RETURN elsifKeyword
    ELSIF name = "END" THEN RETURN endKeyword
    ELSIF name = "EXIT" THEN RETURN exitKeyword
    ELSIF name = "FOR" THEN RETURN forKeyword
    ELSIF name = "IF" THEN RETURN ifKeyword
    ELSIF name = "IMPORT" THEN RETURN importKeyword
    ELSIF name = "IN" THEN RETURN inKeyword
    ELSIF name = "IS" THEN RETURN isKeyword
    ELSIF name = "LOOP" THEN RETURN loopKeyword
    ELSIF name = "MOD" THEN RETURN modKeyword
    ELSIF name = "MODULE" THEN RETURN moduleKeyword
    ELSIF name = "NIL" THEN RETURN nilKeyword
    ELSIF name = "OF" THEN RETURN ofKeyword
    ELSIF name = "OR" THEN RETURN orKeyword
    ELSIF name = "POINTER" THEN RETURN pointerKeyword
    ELSIF name = "PROCEDURE" THEN RETURN procedureKeyword
    ELSIF name = "RECORD" THEN RETURN recordKeyword
    ELSIF name = "REPEAT" THEN RETURN repeatKeyword
    ELSIF name = "RETURN" THEN RETURN returnKeyword
    ELSIF name = "THEN" THEN RETURN thenKeyword
    ELSIF name = "TO" THEN RETURN toKeyword
    ELSIF name = "TYPE" THEN RETURN typeKeyword
    ELSIF name = "UNTIL" THEN RETURN untilKeyword
    ELSIF name = "VAR" THEN RETURN varKeyword
    ELSIF name = "WHILE" THEN RETURN whileKeyword
    ELSIF name = "WITH" THEN RETURN withKeyword
    ELSE RETURN ident
    END
  END LookupKeyword;

  PROCEDURE ScanIdentifier(VAR s: Scanner; VAR t: Token);
    VAR len: INTEGER; ch: CHAR;
  BEGIN
    len := 0;
    ch := CurrentChar(s);
    WHILE IsLetter(ch) OR IsDigit(ch) DO
      IF len < maxLexemeLength THEN
        t.lexeme[len] := ch; INC(len)
      ELSIF len = maxLexemeLength THEN
        Diagnostics.Error(t.line, t.column, "identifier too long, truncated");
        INC(len)
      END;
      Advance(s); ch := CurrentChar(s)
    END;
    IF len > maxLexemeLength THEN len := maxLexemeLength END;
    t.lexeme[len] := 0X;
    t.kind := LookupKeyword(t.lexeme)
  END ScanIdentifier;

  PROCEDURE ScanRealTail(VAR s: Scanner; VAR t: Token; len: INTEGER);
    VAR ch: CHAR;
  BEGIN
    IF len < maxLexemeLength THEN t.lexeme[len] := "."; INC(len) END;
    Advance(s); (* consume '.' *)
    ch := CurrentChar(s);
    WHILE IsDigit(ch) DO
      IF len < maxLexemeLength THEN t.lexeme[len] := ch; INC(len) END;
      Advance(s); ch := CurrentChar(s)
    END;
    t.isLongReal := FALSE;
    IF (ch = "E") OR (ch = "D") THEN
      t.isLongReal := ch = "D";
      IF len < maxLexemeLength THEN t.lexeme[len] := ch; INC(len) END;
      Advance(s); ch := CurrentChar(s);
      IF (ch = "+") OR (ch = "-") THEN
        IF len < maxLexemeLength THEN t.lexeme[len] := ch; INC(len) END;
        Advance(s); ch := CurrentChar(s)
      END;
      WHILE IsDigit(ch) DO
        IF len < maxLexemeLength THEN t.lexeme[len] := ch; INC(len) END;
        Advance(s); ch := CurrentChar(s)
      END
    END;
    IF len > maxLexemeLength THEN len := maxLexemeLength END;
    t.lexeme[len] := 0X;
    t.kind := real
  END ScanRealTail;

  PROCEDURE ScanNumber(VAR s: Scanner; VAR t: Token);
    VAR len: INTEGER; ch: CHAR; allDecimal: BOOLEAN;
  BEGIN
    len := 0; allDecimal := TRUE;
    ch := CurrentChar(s);
    WHILE IsHexDigit(ch) DO
      IF len < maxLexemeLength THEN t.lexeme[len] := ch; INC(len) END;
      IF ~IsDigit(ch) THEN allDecimal := FALSE END;
      Advance(s); ch := CurrentChar(s)
    END;
    IF len > maxLexemeLength THEN len := maxLexemeLength END;
    t.lexeme[len] := 0X;
    t.isHex := FALSE;
    IF ch = "H" THEN
      Advance(s);
      IF len < maxLexemeLength THEN t.lexeme[len] := "H"; t.lexeme[len + 1] := 0X END;
      t.kind := integer; t.isHex := TRUE
    ELSIF ch = "X" THEN
      Advance(s);
      IF len < maxLexemeLength THEN t.lexeme[len] := "X"; t.lexeme[len + 1] := 0X END;
      t.kind := charConst
    ELSIF allDecimal & (ch = ".") & (PeekChar(s, 1) # ".") THEN
      ScanRealTail(s, t, len)
    ELSIF allDecimal THEN
      t.kind := integer
    ELSE
      Diagnostics.Error(t.line, t.column, "invalid number");
      t.kind := integer
    END
  END ScanNumber;

  PROCEDURE ScanString(VAR s: Scanner; VAR t: Token);
    VAR quote, ch: CHAR; len: INTEGER; terminated: BOOLEAN;
  BEGIN
    quote := CurrentChar(s); Advance(s);
    len := 0; terminated := FALSE;
    ch := CurrentChar(s);
    WHILE (~terminated) & (ch # 0X) & (ch # 0AX) DO
      IF ch = quote THEN
        terminated := TRUE
      ELSE
        IF len < maxLexemeLength THEN
          t.lexeme[len] := ch; INC(len)
        ELSIF len = maxLexemeLength THEN
          Diagnostics.Error(t.line, t.column, "string too long, truncated");
          INC(len)
        END;
        Advance(s); ch := CurrentChar(s)
      END
    END;
    IF terminated THEN
      Advance(s)
    ELSE
      Diagnostics.Error(t.line, t.column, "unterminated string")
    END;
    IF len > maxLexemeLength THEN len := maxLexemeLength END;
    t.lexeme[len] := 0X;
    t.kind := string
  END ScanString;

  PROCEDURE ScanSymbol(VAR s: Scanner; VAR t: Token);
    VAR ch: CHAR;
  BEGIN
    ch := CurrentChar(s);
    t.lexeme[0] := ch; t.lexeme[1] := 0X;
    Advance(s);
    CASE ch OF
      "+": t.kind := plus
    | "-": t.kind := minus
    | "*": t.kind := times
    | "/": t.kind := slash
    | "~": t.kind := tilde
    | "&": t.kind := ampersand
    | ",": t.kind := comma
    | ";": t.kind := semicolon
    | "|": t.kind := verticalBar
    | "(": t.kind := leftParen
    | ")": t.kind := rightParen
    | "[": t.kind := leftBracket
    | "]": t.kind := rightBracket
    | "{": t.kind := leftBrace
    | "}": t.kind := rightBrace
    | "^": t.kind := caret
    | "=": t.kind := equal
    | "#": t.kind := notEqual
    | ".":
        IF CurrentChar(s) = "." THEN
          t.lexeme[1] := "."; t.lexeme[2] := 0X; Advance(s); t.kind := upTo
        ELSE
          t.kind := period
        END
    | ":":
        IF CurrentChar(s) = "=" THEN
          t.lexeme[1] := "="; t.lexeme[2] := 0X; Advance(s); t.kind := assign
        ELSE
          t.kind := colon
        END
    | "<":
        IF CurrentChar(s) = "=" THEN
          t.lexeme[1] := "="; t.lexeme[2] := 0X; Advance(s); t.kind := lessEqual
        ELSE
          t.kind := less
        END
    | ">":
        IF CurrentChar(s) = "=" THEN
          t.lexeme[1] := "="; t.lexeme[2] := 0X; Advance(s); t.kind := greaterEqual
        ELSE
          t.kind := greater
        END
    ELSE
      Diagnostics.Error(t.line, t.column, "invalid character");
      t.kind := invalid
    END
  END ScanSymbol;

  PROCEDURE InitScanner*(VAR s: Scanner; text: CharBuffer; length: LONGINT);
  BEGIN
    s.text := text; s.length := length; s.pos := 0;
    s.line := 1; s.column := 1
  END InitScanner;

  PROCEDURE NextToken*(VAR s: Scanner; VAR t: Token);
    VAR ch: CHAR;
  BEGIN
    SkipWhiteSpaceAndComments(s);
    t.line := s.line; t.column := s.column;
    t.isHex := FALSE; t.isLongReal := FALSE;
    ch := CurrentChar(s);
    IF ch = 0X THEN
      t.kind := eof; t.lexeme[0] := 0X
    ELSIF IsLetter(ch) THEN
      ScanIdentifier(s, t)
    ELSIF IsDigit(ch) THEN
      ScanNumber(s, t)
    ELSIF (ch = '"') OR (ch = "'") THEN
      ScanString(s, t)
    ELSE
      ScanSymbol(s, t)
    END
  END NextToken;

  PROCEDURE KindName*(kind: INTEGER; VAR name: ARRAY OF CHAR);
  BEGIN
    CASE kind OF
      eof: COPY("eof", name)
    | ident: COPY("ident", name)
    | integer: COPY("integer", name)
    | real: COPY("real", name)
    | charConst: COPY("charConst", name)
    | string: COPY("string", name)
    | invalid: COPY("invalid", name)
    | plus: COPY("plus", name)
    | minus: COPY("minus", name)
    | times: COPY("times", name)
    | slash: COPY("slash", name)
    | tilde: COPY("tilde", name)
    | ampersand: COPY("ampersand", name)
    | period: COPY("period", name)
    | comma: COPY("comma", name)
    | semicolon: COPY("semicolon", name)
    | verticalBar: COPY("verticalBar", name)
    | leftParen: COPY("leftParen", name)
    | rightParen: COPY("rightParen", name)
    | leftBracket: COPY("leftBracket", name)
    | rightBracket: COPY("rightBracket", name)
    | leftBrace: COPY("leftBrace", name)
    | rightBrace: COPY("rightBrace", name)
    | assign: COPY("assign", name)
    | caret: COPY("caret", name)
    | equal: COPY("equal", name)
    | notEqual: COPY("notEqual", name)
    | less: COPY("less", name)
    | greater: COPY("greater", name)
    | lessEqual: COPY("lessEqual", name)
    | greaterEqual: COPY("greaterEqual", name)
    | upTo: COPY("upTo", name)
    | colon: COPY("colon", name)
    | arrayKeyword: COPY("ARRAY", name)
    | beginKeyword: COPY("BEGIN", name)
    | byKeyword: COPY("BY", name)
    | caseKeyword: COPY("CASE", name)
    | constKeyword: COPY("CONST", name)
    | divKeyword: COPY("DIV", name)
    | doKeyword: COPY("DO", name)
    | elseKeyword: COPY("ELSE", name)
    | elsifKeyword: COPY("ELSIF", name)
    | endKeyword: COPY("END", name)
    | exitKeyword: COPY("EXIT", name)
    | forKeyword: COPY("FOR", name)
    | ifKeyword: COPY("IF", name)
    | importKeyword: COPY("IMPORT", name)
    | inKeyword: COPY("IN", name)
    | isKeyword: COPY("IS", name)
    | loopKeyword: COPY("LOOP", name)
    | modKeyword: COPY("MOD", name)
    | moduleKeyword: COPY("MODULE", name)
    | nilKeyword: COPY("NIL", name)
    | ofKeyword: COPY("OF", name)
    | orKeyword: COPY("OR", name)
    | pointerKeyword: COPY("POINTER", name)
    | procedureKeyword: COPY("PROCEDURE", name)
    | recordKeyword: COPY("RECORD", name)
    | repeatKeyword: COPY("REPEAT", name)
    | returnKeyword: COPY("RETURN", name)
    | thenKeyword: COPY("THEN", name)
    | toKeyword: COPY("TO", name)
    | typeKeyword: COPY("TYPE", name)
    | untilKeyword: COPY("UNTIL", name)
    | varKeyword: COPY("VAR", name)
    | whileKeyword: COPY("WHILE", name)
    | withKeyword: COPY("WITH", name)
    ELSE COPY("?", name)
    END
  END KindName;

END Lexer.
