MODULE openarrays;
  (* Oberon2.pdf 6.2: an open array is only a pointer's base, an open
     array's element or a formal parameter's type (voc: err 88) *)
  TYPE A = ARRAY OF INTEGER; T = RECORD f: ARRAY OF CHAR; g: A END;
    F = ARRAY 3 OF ARRAY OF INTEGER; F2 = ARRAY 3, 4 OF A;
    OK1 = POINTER TO ARRAY OF ARRAY OF CHAR; OK2 = POINTER TO A;
    OK3 = PROCEDURE (x: ARRAY OF A);
  VAR o: ARRAY OF INTEGER; o2: A; r: RECORD h: A END;
  PROCEDURE P(x: A; VAR y: ARRAY OF CHAR); VAR l: ARRAY OF CHAR; END P;
END openarrays.
