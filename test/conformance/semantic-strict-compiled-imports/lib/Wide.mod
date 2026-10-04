MODULE Wide;
  (* HUGEINT in an interface: an extension, which -strict must not report
     in an importer's build *)
  PROCEDURE Big*(): HUGEINT;
  BEGIN RETURN 5
  END Big;
END Wide.
