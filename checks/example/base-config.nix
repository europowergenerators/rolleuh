{ lib, config, modulesPath, ... }: {
  imports = [
    #(modulesPath + "/profiles/minimal.nix")
    (modulesPath + "/virtualisation/qemu-vm.nix")
    (modulesPath + "/testing/test-instrumentation.nix") # For automated test runs!
    {
      key = "no-manual";
      documentation.nixos.enable = false;
    }
    {
      key = "no-revision";
      # Make the revision metadata constant, in order to avoid needless retesting.
      # The human version (e.g. 21.05-pre) is left as is, because it is useful
      # for external modules that test with e.g. testers.nixosTest and rely on that
      # version number.
      config.system.nixos = {
        revision = lib.mkForce "constant-nixos-revision";
        versionSuffix = lib.mkForce "test";
        label = lib.mkForce "test";
      };
    }
    # (
    #   { config, ... }:
    #   {
    #     # Don't pull in switch-to-configuration by default, except when specialisations or early boot shenanigans are involved.
    #     # This is mostly a Hydra optimization, so we don't rebuild all the tests every time switch-to-configuration-ng changes.
    #     key = "no-switch-to-configuration";
    #     system.switch.enable = lib.mkDefault (
    #       config.isSpecialisation || config.specialisation != { } || config.virtualisation.installBootLoader
    #     );
    #   }
    # )
  ];

  virtualisation.graphics = false;
  boot.loader.grub.enable = false;
  # Required to keep backdoor service alive for instrumenting the VM's
  # testing.initrdBackdoor = true;
  # boot.initrd.systemd.enable = true;

  users.mutableUsers = false;

  services.openssh = {
    enable = true;
    settings.KbdInteractiveAuthentication = false;
    settings.PasswordAuthentication = true;
  };

  system.stateVersion = config.system.nixos.release;
}
