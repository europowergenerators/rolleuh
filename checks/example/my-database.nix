{ lib, ... }: {
  imports = [ ./base-config.nix ];

  services.openssh.settings.PermitRootLogin = "yes";
  users.users.root.password = "testing";
  users.users.root.hashedPasswordFile = lib.mkForce null; # Silence password warning

  services.postgresql.enable = true;
  # TODO
}
