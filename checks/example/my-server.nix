{ ... }: {
  imports = [ ./base-config.nix ];
  services.nginx.enable = true;

  users.users.deploy = {
    extraGroups = [ "wheel" ];
    password = "testing";
    isNormalUser = true;
  };

  nix.settings.trusted-users = [ "deploy" ];
  security.sudo.extraRules = [{
    users = [ "deploy" ];
    commands = [{
      command = "ALL";
      options = [ "NOPASSWD" ];
    }];
  }];

  # TODO
}
