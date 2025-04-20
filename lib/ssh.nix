_:

{
  mkPubKey = name: type: publicKey: {
    "${name}-${type}" = {
      hostNames = [ name ];
      publicKey = "${type} ${publicKey}";
    };
  };
}
