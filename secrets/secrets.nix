# ragenix rules file: maps each secret to the public keys that may decrypt it.
# Edit secrets from inside this directory:  cd secrets && ragenix -e <name>.age
# After changing recipients:                ragenix --rekey
let
  # user keys (for editing/rekeying secrets)
  natsume = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO5cvA90dd+syRxeLBrQEdwBGmM4kC4pZBcbnya1g5sw";
  hawken-rives = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILFhbHFf1LJ/NseB3yDEAKNu3CGNDs+ot8qdQA5LI4rU";
  users = [
    natsume
    hawken-rives
  ];

  # host keys (each host decrypts its own secrets at activation via
  # /etc/ssh/ssh_host_ed25519_key)
  nutmeg = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINRtF1Gu1NN25zb3ZWL+D2XBn2i0FszefxLVMwhItgOb";
  techcyte = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEZW19gGFVWa3uCxOv4CHItnUuucmNQiExpgMAqTUSNO";
  systems = [
    nutmeg
    techcyte
  ];
in {
  # Example secret proving the workflow end-to-end. Wired on nutmeg only.
  "example.age".publicKeys = users ++ [nutmeg];

  # paperless superuser password (nutmeg).
  "paperless-admin-pass.age".publicKeys = users ++ [nutmeg];

  # peertube signing secret (nutmeg).
  "peertube-secret.age".publicKeys = users ++ [nutmeg];
}
