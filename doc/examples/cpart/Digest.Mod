MODULE Digest;
  IMPORT Out, Hash;
BEGIN
  Out.Hex(Hash.Of("Oberon"), 8); Out.Ln
END Digest.
