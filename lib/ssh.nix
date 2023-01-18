_:

{
  mkPubKey = name: type: publicKey: {
    "${name}-${type}" = {
      extraHostNames = [ name ];
      publicKey = "${type} ${publicKey}";
    };
  };
}
