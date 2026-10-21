# GEEKOM A9 Max — host-specific configuration.
# Ryzen AI 9 HX 370 (Zen 5), Radeon 890M (RDNA 3.5), 64 GB DDR5 (54.5 GiB
# usable), 2 TB NVMe, MediaTek MT7925 Wi-Fi 7 + Bluetooth. Shared settings
# live in modules/nixos/common.nix.
{
  pkgs,
  # nixos-unstable nixpkgs; the guard rule for referencing it is in flake.nix
  # (specialArgs).
  unstablePkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix

    # Cold-boot enumeration failure of the Razer Basilisk V3; auto-bounces the
    # mouse's xHCI controller when it is absent. Geekom-only IDs, so it lives
    # with this host — see doc/troubleshooting.md.
    ./usb-mouse-recovery.nix

    # greetd + noctalia-greeter: the only path in now that session = "niri"
    # dropped GDM. Host-local like usb-mouse-recovery.nix: hplaptop keeps GDM
    # and must not see greetd.
    ./greeter.nix
  ];

  networking.hostName = "geekom";

  # NVRAM writes are safe and wanted on real UEFI hardware; the VM sets this
  # false.
  boot.loader.efi.canTouchEfiVariables = true;

  # 20s rather than the 5s default: this boot menu is the only recovery path,
  # and 5 seconds is too short to catch when walking up to a machine that is
  # already POSTing. The VM keeps the default.
  boot.loader.timeout = 20;

  # amdgpu (Radeon 890M microcode) and the MT7925 combo radio — Wi-Fi and,
  # separately, its USB-attached Bluetooth side — need these blobs; without
  # them: black screen, no network.
  hardware.enableRedistributableFirmware = true;

  hardware.cpu.amd.updateMicrocode = true;

  # amdgpu from the initrd so the console comes up on the real driver rather
  # than handing over from simpledrm partway through boot.
  #
  # Deliberately NOT set: `services.xserver.videoDrivers` (that is the X11
  # driver path — amdgpu is a kernel driver and KMS is automatic; naming it
  # there is a common copy-paste that does nothing useful),
  # `hardware.amdgpu.opencl.enable` (ROCm — inference runs on Vulkan here, see
  # the ollama package below) and `boot.kernelPackages` (the 26.05 default
  # kernel is new enough for both Strix Point and MT7925).
  hardware.amdgpu.initrd.enable = true;

  # THIS BOX CANNOT SUSPEND, so nothing is allowed to try — see
  # doc/bare-metal-geekom.md. Masked at the SYSTEM level on purpose: the obvious
  # fix (a desktop's power settings) writes to the logged-in user's dconf,
  # while the login greeter runs as its own user outside any desktop's power
  # settings — which is how the machine was lost while nobody was logged in.
  # Masking the targets is the only form that covers the greeter, every user
  # session, AND the power menu entry. hibernate and hybrid-sleep cost nothing:
  # both need swap, and this disk layout creates none.
  #
  # Do NOT "fix" this with mem_sleep_default=deep. `deep` is absent from
  # mem_sleep, so the kernel parameter is a silent no-op that reads as a
  # solution.
  systemd.targets = {
    sleep.enable = false;
    suspend.enable = false;
    hibernate.enable = false;
    hybrid-sleep.enable = false;
  };

  # The desktop seam — pipewire, Brave, Bluetooth, ghostty — defined in
  # modules/nixos/desktop.nix, which every host imports but only this one
  # switches on.
  local.desktop.enable = true;

  # niri is THE session, not one of two: `session = "niri"` drops the X
  # server, GDM and GNOME (modules/nixos/desktop.nix), and ./greeter.nix makes
  # greetd + noctalia-greeter the only path in. niri 26.04 with the Noctalia
  # shell (config/niri/, config/noctalia/); Noctalia's config is HM-owned
  # behind the same switch (modules/home/niri.nix).
  #
  # No session chooser and no autologin: noctalia-greeter asks for the password and
  # starts the one session there is. Getting out is Noctalia's Log out
  # (`niri msg action quit`), which lands back in the greeter.
  #
  # The two packages that make that session usable live in the systemPackages
  # list below, next to Vial:
  #   noctalia           — the shell. From nixpkgs, not upstream's flake: the
  #                        flake pins its own nixpkgs (a second glibc, pipewire
  #                        and systemd generation, ~805 MiB marginal) or, with
  #                        `follows`, builds from source and misses its cache.
  #                        Revisit when nixos-26.05 carries 5.3.x.
  #   xwayland-satellite — niri's X11 integration needs this ON PATH; the
  #                        nixpkgs module passes enableXWayland = false, so
  #                        without it every X11 app is unavailable and niri
  #                        logs "error spawning xwayland-satellite".
  local.desktop.session = "niri";
  programs.niri.enable = true;
  # The channel's niri 26.04 still ships a niri-session that calls the
  # blanket `systemctl --user import-environment`; systemd 260 answers that
  # with "Calling import-environment without a list of variable names is
  # deprecated", and niri-session runs with its stdout on the login VT, so
  # the warning prints on screen during login. Upstream fixed it (niri
  # 4adbf00) but no release carries it yet, so the fixed script is carried
  # in config/niri/niri-session and installed OVER the packaged one.
  #
  # Installed after the build, not patched into the source: niri is a
  # buildRustPackage, so patching its tree would invalidate the cargo build
  # and rebuild niri from source on every CI run (~15 min). Replacing one
  # installed script leaves the Rust build untouched and cache-substitutable
  # (the join builds in seconds).
  #
  # The guard fails the build once the packaged script no longer has the
  # blanket call — that is the signal that upstream shipped the fix, and this
  # override and config/niri/niri-session should both be deleted.
  programs.niri.package =
    (pkgs.symlinkJoin {
      name = "niri-session-fixed";
      paths = [ pkgs.niri ];
      postBuild = ''
        if ! grep -q "systemctl --user import-environment" $out/bin/niri-session; then
          echo "!! the packaged niri-session no longer has the blanket import:" >&2
          echo "!! upstream shipped the fix — delete this override and" >&2
          echo "!! config/niri/niri-session." >&2
          exit 1
        fi
        rm -f $out/bin/niri-session
        cp ${../../config/niri/niri-session} $out/bin/niri-session
        chmod +x $out/bin/niri-session
        patchShebangs $out/bin/niri-session
      '';
    }).overrideAttrs
      (_: {
        # The nixpkgs module puts this package in displayManager.sessionPackages,
        # which asserts the package carries `providedSessions`; symlinkJoin does
        # not inherit the passthru of the package it joins.
        passthru.providedSessions = pkgs.niri.providedSessions;
      });
  # Recording backend for Noctalia's screen_recorder plugin (config/noctalia/
  # config.toml): the module wraps gsr-kms-server with cap_sys_admin+ep, so
  # capture is promptless — the xdg-desktop-portal-gnome chooser this avoids
  # does not render under niri (xdg-desktop-portal#2039).
  programs.gpu-screen-recorder.enable = true;

  # Explicit-enable trio for the niri session, each currently a GNOME
  # `mkDefault` the greetd cutover would otherwise silently remove with GNOME:
  # ibus off kills the keyboard-notification autostart entry (its NotShowIn
  # fires under niri), dconf serves HM `dconf.settings`, gnome-keyring backs
  # the lock screen's PAM unlock. Same pattern as bluetooth in
  # modules/nixos/desktop.nix.
  i18n.inputMethod.enable = false;
  programs.dconf.enable = true;
  services.gnome.gnome-keyring.enable = true;

  # Steam + Vulkan (RADV for the Radeon 890M), same pattern — defined in
  # modules/nixos/gaming.nix.
  local.gaming.enable = true;

  # nix-ld, ollama, nodejs, uv, jq, sshd — gated behind `local.dev.enable` in
  # modules/nixos/dev.nix.
  local.dev.enable = true;

  # `nrs`/`nrt` activate over SSH to THIS machine, so phase 1 cannot be killed
  # by the display stack restarting (doc/workflow.md, "never run nrs from the
  # graphical console"). sshd itself comes from dev.enable above; the two keys
  # are this box's own identities and are literals on purpose — the module
  # explains why. The user key is the one in ~/.ssh/id_ed25519 here, NOT the
  # Mac's key from user.nix: its private half must never be copied.
  local.loopbackRebuild = {
    enable = true;
    authorizedKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBYpUmfHJCHzd7NYBCi0N1DXpgkDfPqdwQfKoZOogXaP andrea@geekom";
    hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINr69uM9JxAJZ0bldSEP3wdIQsyfa9n7jBKTERXEHQF/ root@geekom";
  };

  # Stated here, not inherited from the gaming module: the Vulkan userspace
  # driver (RADV, via mesa) reaches userspace through this option, and GPU
  # inference must not depend on whether this box also games. Same value the
  # gaming module sets, so no closure moves either way.
  hardware.graphics.enable = true;

  # Local LLM inference on the Radeon 890M. dev.nix enables the service with
  # the CPU-only default package; this host swaps the build, and only on this
  # host. VULKAN, NOT ROCM: this GPU is gfx1150, where ROCm measured 6.42 tok/s
  # against 15.94 tok/s CPU-only on this exact part (ollama#9999), so the
  # acceleration ran 2.5x slower than none. Revisit only with a measurement,
  # not with a release note. The package comes from nixos-unstable
  # (doc/workflow.md, adoption list); the measured record is doc/local-llm.md.
  services.ollama.package = unstablePkgs.ollama-vulkan;

  # The FULL 262144 the GGUF declares. Without it, 0.32+'s vram-based default
  # context tiering picks 32768, and clients discover the effective limit from
  # the daemon (omp reads it via /api/show) — this env is the single place the
  # window is set. Per-request num_ctx still overrides it downward; a
  # dense-attention model would NOT get this treatment — measure first
  # (doc/local-llm.md has the KV math and the measurements).
  services.ollama.environmentVariables.OLLAMA_CONTEXT_LENGTH = "262144";

  # 1h, not the 5m default: a reload of this model costs 11-14 s and sessions
  # idle longer than that between prompts. `-1` was rejected — 22 GiB would
  # never free on a machine that also games (doc/local-llm.md).
  services.ollama.environmentVariables.OLLAMA_KEEP_ALIVE = "1h";

  # OLLAMA_IGPU_ENABLE IS NOT OPTIONAL HERE: since 0.32 ollama discovers
  # integrated GPUs and then discards them, falling back to CPU — the
  # ollama-vulkan package above is inert without this, and the daemon still
  # starts and answers every request while never touching the GPU. `ollama ps`
  # showing "100% GPU" is the check (doc/local-llm.md).
  services.ollama.environmentVariables.OLLAMA_IGPU_ENABLE = "1";

  services.fwupd.enable = true;

  # Dockerd + compose for development — defined in modules/nixos/docker.nix,
  # which every host imports but only this one switches on. It also puts this
  # user in the `docker` group, which is root-equivalent; the module says what
  # that does and does not cost.
  local.docker.enable = true;

  # Vial — GUI for configuring QMK/VIA keyboards in real time. Here and not in
  # modules/nixos/desktop.nix: it is for a physical keyboard on this box, not a
  # general desktop app. The package's own rule is MODE=0666 on EVERY hidraw
  # device, so it is not installed; this is that rule narrowed to Vial
  # controllers by the serial their firmware reports, with an ACL for the
  # active session instead of world-write.
  environment.systemPackages = [
    # Vial, above.
    pkgs.vial

    # The niri session's shell and its X11 bridge, for the reasons given at
    # `programs.niri.enable`.
    pkgs.noctalia
    # TRIAL (uncommitted): greeter packages on PATH for the greeter user and
    # the polkit action under /share/polkit-1 (pkexec appearance sync).
    pkgs.noctalia-greeter
    pkgs.xwayland-satellite

    # Region picker for the screen_recorder plugin's default (region) source.
    pkgs.slurp
  ];
  services.udev.extraRules = ''KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{serial}=="*vial:f64c2b3c*", MODE="0660", TAG+="uaccess"'';

  # Set once at install; never bump (doc/workflow.md).
  system.stateVersion = "26.05";
}
