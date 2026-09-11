# GEEKOM A9 Max — host-specific configuration.
# Ryzen AI 9 HX 370 (Zen 5), Radeon 890M (RDNA 3.5), 64 GB DDR5-5600 (2x32 GB,
# 54.5 GiB usable), 2 TB NVMe,
# MediaTek MT7925 Wi-Fi 7 + Bluetooth combo radio.
# Shared settings live in modules/nixos/common.nix.
{
  pkgs,
  # The nixos-unstable nixpkgs instance, bound only on this host (flake.nix
  # `hostArgs`). Exists for exactly one package today: ollama-vulkan, below.
  unstablePkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix

    # Cold-boot enumeration failures of the Razer Basilisk V3 (front AND rear
    # ports — see doc/troubleshooting.md and the module's header for why
    # port choice does not fix it). Auto-bounces the mouse's xHCI controller
    # at boot when the mouse is absent; no-op on clean boots.
    ../../modules/nixos/usb-mouse-recovery.nix
  ];

  # Network identity
  networking.hostName = "geekom";

  # Real UEFI hardware, so writing boot entries into firmware NVRAM is both
  # safe and wanted. The VM sets this false — it has no persistent NVRAM.
  boot.loader.efi.canTouchEfiVariables = true;

  # 20s rather than the 5s default. This box's boot menu is its only recovery
  # path, and 5 seconds is not enough to catch when walking up to a machine that
  # is already POSTing. The VM keeps the default: it is reachable over ssh and
  # rebuildable from the Mac, so a missed menu costs nothing there.
  boot.loader.timeout = 20;

  # Redistributable firmware blobs. Load-bearing THREE separate times here:
  #   1. amdgpu       — the Radeon 890M will not initialise without RDNA 3.5
  #                     microcode; the console falls back to simpledrm at best
  #   2. MT7925 Wi-Fi — MediaTek Wi-Fi 7
  #   3. MT7925 Bluetooth — the SAME combo radio, but its BT side is a separate
  #                     USB-attached device driven by btusb, needing its own
  #                     blob (BT_RAM_CODE_MT7925_1_1_hdr.bin)
  # Omitting this is the difference between a working desktop and a black
  # screen with no network and no keyboard-adjacent way to fix it.
  hardware.enableRedistributableFirmware = true;

  # Zen 5 microcode updates.
  hardware.cpu.amd.updateMicrocode = true;

  # Load amdgpu from the initrd so the console comes up on the real driver
  # rather than handing over from simpledrm partway through boot.
  #
  # Deliberately NOT set: `services.xserver.videoDrivers` (that is the X11
  # driver path — amdgpu is a kernel driver and KMS is automatic; naming it
  # there is a common copy-paste that does nothing useful), and
  # `hardware.amdgpu.opencl.enable` (ROCm). Local inference runs on Vulkan
  # here, not ROCm — see the services.ollama.package note below.
  #
  # Also deliberately NOT set: `boot.kernelPackages`. The 26.05 default kernel
  # is new enough for both Strix Point and MT7925; pinning latest here would
  # trade a working default for a moving target.
  hardware.amdgpu.initrd.enable = true;

  # THIS BOX CANNOT SUSPEND, so nothing is allowed to try. The firmware advertises
  # S0 S4 S5 — no S3 — and /sys/power/mem_sleep offers only [s2idle]. Resume hangs
  # hard: the journal stops dead at "Performing sleep operation 'suspend'" with not
  # one line after it, the display gets no signal, the radio drops off the LAN, and
  # a 10-second power-button hold is the only way back. Observed twice, 2026-08-09
  # and 2026-08-10.
  #
  # Masked at the SYSTEM level on purpose. The obvious fix — GNOME Settings →
  # Power → Automatic Suspend — writes to the logged-in user's dconf, and GDM's
  # greeter runs as its own user (uid 60578) with its own dconf and its own 900s
  # idle timer. That is exactly how the machine was lost on 2026-08-10: nobody had
  # logged in, so the greeter suspended it 15 minutes after boot while the user
  # session toggle sat there looking correct. Masking the targets is the only form
  # that covers the greeter, every user session, AND the power menu entry.
  #
  # hibernate and hybrid-sleep are masked too and cost nothing: both need swap, and
  # this disk layout creates none.
  #
  # Do NOT "fix" this with mem_sleep_default=deep. `deep` is absent from
  # mem_sleep, so the kernel parameter is a silent no-op that reads as a solution.
  systemd.targets = {
    sleep.enable = false;
    suspend.enable = false;
    hibernate.enable = false;
    hybrid-sleep.enable = false;
  };

  # Graphical target: GDM + GNOME, pipewire, Brave, Bluetooth, ghostty.
  # Defined in modules/nixos/desktop.nix, which every host imports but only
  # this one switches on.
  local.desktop.enable = true;

  # Gaming: Steam + Vulkan (RADV for the Radeon 890M). Defined in
  # modules/nixos/gaming.nix, which every host imports but only this one
  # switches on.
  local.gaming.enable = true;

  # Dev tooling — nix-ld, ollama, opencode, nodejs, uv, jq, sshd — is gated
  # behind `local.dev.enable` in modules/nixos/dev.nix. This host flips it on.
  local.dev.enable = true;

  # Loopback rebuilds: `nrs`/`nrt` (modules/home/shell.nix) run the activation
  # over SSH to THIS machine, so phase 1 cannot be killed by the display stack
  # restarting — doc/workflow.md's "never run nrs from the graphical console"
  # hazard, discharged without a second machine (the old workaround was:
  # rebuild from the Mac over SSH, or from the console only via nrb + reboot).
  #
  # sshd itself comes from dev.enable above; these two keys are this box's
  # own identities — the user key that lives in ~/.ssh/id_ed25519 here (NOT
  # the Mac's key from user.nix: its private half must never be copied), and
  # the sshd host key pinned into known-hosts so the manual ssh-keyscan step
  # is gone. The module file explains why they are literals.
  local.loopbackRebuild = {
    enable = true;
    authorizedKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBYpUmfHJCHzd7NYBCi0N1DXpgkDfPqdwQfKoZOogXaP andrea@geekom";
    hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINr69uM9JxAJZ0bldSEP3wdIQsyfa9n7jBKTERXEHQF/ root@geekom";
  };

  # Local LLM inference on the Radeon 890M. dev.nix enables the service with
  # the CPU-only default package; this swaps the build, and only on this host.
  #
  # VULKAN, NOT ROCM, and that is not the obvious choice. This GPU is gfx1150,
  # which ROCm has handled badly: ollama#9999 measured 6.42 tok/s on ROCm
  # against 15.94 tok/s CPU-only on this exact part — acceleration that ran
  # 2.5x SLOWER than no acceleration. Upstream now lists gfx1150 as supported,
  # so that may be fixed, but Vulkan also skips the multi-GB ROCm closure and
  # can spill into GTT when a model outgrows the 8GB VRAM carve-out. Revisit
  # only with a measurement, not with a release note.
  #
  # The Vulkan userspace driver (RADV, via mesa) reaches userspace through
  # `hardware.graphics.enable`, which is now stated explicitly below rather
  # than inherited. It used to arrive ONLY as a side effect of the gaming
  # module, so turning gaming off dropped inference back to CPU silently: the
  # daemon still started and still answered, just slowly, with nothing in the
  # journal naming the cause.
  #
  # No systemd changes needed: the upstream unit already ships
  # SupplementaryGroups=render, DeviceAllow=char-drm and PrivateDevices=false,
  # so the DynamicUser can reach /dev/dri/renderD128 as-is.
  # Stated here, not left to the gaming module. Verified 2026-08-31 that on
  # this host the option is defined only by modules/nixos/gaming.nix and
  # nixpkgs' programs/steam.nix — nothing else. GPU inference should not
  # depend on whether this box also games. Same value the gaming module sets,
  # so the closure does not move while gaming stays on; the point is that it
  # would not move if gaming were switched off either.
  hardware.graphics.enable = true;

  # UNSTABLE, NOT STABLE — a documented policy change (2026-09-11), reversing
  # doc/workflow.md's earlier "not ollama" caution, which was written without
  # measurements. The measured story (doc/local-llm.md):
  #   * 0.32.15 caches resolved model metadata between requests, cutting
  #     time-to-first-token roughly in half (995 -> 524 ms in upstream's bench)
  #   * 0.33.0 fixes agent prefill-restore: a cancelled/retried opencode request
  #     on a recurrent-layer model like this one could reprocess from zero
  #   * 0.33.3 honors GGUF-defined default parameters
  # That is functional gain, not cosmetic, and the "mid-cycle llama.cpp bump"
  # risk the old note warned about is discharged by the same verification gate
  # as any change: this box's MTP/Vulkan placement checks after every rebuild
  # (see the OLLAMA_IGPU_ENABLE comment below). The version is re-pinned by
  # `nix flake lock --update-input nixpkgs-unstable` on OUR schedule, so the
  # moving-target objection does not apply either.
  services.ollama.package = unstablePkgs.ollama-vulkan;

  # Daemon default context: the FULL 262144 the GGUF declares. Without this,
  # 0.32+'s "vram-based default context" tiering picks 32768 — the >=23GiB
  # bracket — because the runner pool is 35.3 GiB (8 GiB VRAM carve-out plus
  # amdgpu's default GTT of half of RAM, 27.3 GiB, reached through Vulkan).
  #
  # This model is a Qwen3-Next-style HYBRID (qwen35moe): only 11 of its 41
  # layers do full attention (full_attention_interval 4; the rest are
  # linear/recurrent), with GQA at 2 KV heads x 256 head_dim. The KV cache is
  # therefore ~22 KB/token, NOT the ~256 KB/token a dense model of this size
  # would need — 5.5 GiB at 262144, measured on the 0.33.3 runner logs
  # (llama_kv_cache lines). Measured decode is FLAT from 22k to 262k context
  # depth (29-31 tok/s), and the full-window load fits GTT with ~9 GiB
  # headroom. Modules/home/opencode.nix already declares limit.context =
  # 262144 for this model: until now the daemon's 32768 default silently
  # overrode it per request (opencode sends no num_ctx); now the two agree.
  #
  # Per-request num_ctx still overrides this downward; smaller models with a
  # dense-attention cache would NOT get this treatment — measure first
  # (doc/local-llm.md).
  services.ollama.environmentVariables.OLLAMA_CONTEXT_LENGTH = "262144";

  # 1h, not the 5m default. A reload of this model costs 11-14 s (20.4 GiB of
  # weights read from NVMe; the runner itself starts in ~4 s, the rest is
  # tensor paging) and opencode sessions idle longer than 5 minutes between
  # prompts. After 1h the model unloads itself and RAM returns to games —
  # "infinite" (-1) was rejected: 22 GiB would never free on a machine that
  # also games. This does NOT preload at boot; the first request pays the
  # load, everything within the hour pays nothing.
  services.ollama.environmentVariables.OLLAMA_KEEP_ALIVE = "1h";

  # OLLAMA_IGPU_ENABLE IS NOT OPTIONAL HERE. Since 0.32 ollama discovers
  # integrated GPUs and then deliberately discards them, logging
  # "dropping integrated GPU; to enable, set OLLAMA_IGPU_ENABLE=1" at INFO and
  # falling back to CPU. Without this the ollama-vulkan package above is inert:
  # the daemon starts, answers every request, and looks entirely healthy while
  # never touching the GPU. `ollama ps` showing "100% GPU" is the check.
  #
  # This is also what lifts the memory ceiling. The amdgpu carve-out is 8 GiB
  # (mem_info_vram_total), but Vulkan reaches system RAM through GTT — 27.3
  # GiB by default (half of the 54.5 GiB usable RAM), so the runner reports a
  # ~35.3 GiB usable pool. The earlier "~19.5GiB" figure in this comment was
  # measured when the box had 32 GB; with the DIMM upgrade the pool grew with
  # the RAM. Measured memory split at 262144 ctx: 20.4 GiB weights (Vulkan0) +
  # 5.5 GiB KV + ~0.3 GiB compute, ~9 GiB GTT headroom.
  #
  # Worth knowing what this does and does not buy, measured on qwen2.5-coder
  # with an identical FIM prompt: 3B goes 20 -> 22 tok/s, 1.5B goes 37 -> 41.
  # About 10%, because the iGPU shares the CPU's LPDDR5x and token decode is
  # bandwidth-bound, not ALU-bound. The real gain is that inference stops
  # competing with the editor for cores.
  services.ollama.environmentVariables.OLLAMA_IGPU_ENABLE = "1";

  # Firmware updates via fwupd + the LVFS. Real UEFI hardware, same as the
  # laptop. hosts/hplaptop/default.nix said "geekom has this too" before this
  # line existed, which made that comment false; adding it here is what makes
  # it true rather than editing the claim away.
  services.fwupd.enable = true;

  # Docker: dockerd + compose, for development. Defined in
  # modules/nixos/docker.nix, which every host imports but only this one
  # switches on. It also puts this user in the `docker` group, which is
  # root-equivalent — the module says what that does and does not cost.
  local.docker.enable = true;

  # Vial — GUI for configuring QMK/VIA keyboards in real time. Lives here and
  # not in modules/nixos/desktop.nix because it is for a physical keyboard
  # plugged into this box, not a general desktop app. The udev rules shipped
  # by the package are what let the GUI talk to the controller without root;
  # without them Vial opens but sees no device.
  environment.systemPackages = [ pkgs.vial ];
  services.udev.packages = [ pkgs.vial ];

  # Set-once: pin state-format defaults to the install release. Never bump casually.
  system.stateVersion = "26.05";
}
