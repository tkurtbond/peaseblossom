MODULE Elided;
  (* ":= .." is how a .sym file says a field has an initializer; it is not
     an initializer in a module *)
  TYPE R = RECORD x: INTEGER := .. END;
END Elided.
