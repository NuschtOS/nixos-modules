_:

{
  mkPubKey = name: type: publicKey: {
    "${name}-${type}" = {
      extraHostNames = [ name ];
      inherit publicKey;
    };
  };
}
