{pkgs, ...}: {
  # SMART health and drive temps for the Mac Mini's SATA SSD. This is opt-in per
  # host because it grants the agent CAP_SYS_RAWIO/CAP_SYS_ADMIN and drops
  # NoNewPrivileges + PrivateDevices — worth it on real hardware, pointless on
  # the tuckles VM. The hub runs on potato-bunny (hosts/potato-bunny/beszel-hub.nix).
  services.beszel.agent.smartmon.enable = true;

  # GPU usage for the HD 4000 iGPU. intel_sysfs (the module's pick for the
  # intel driver) needs an hwmon energy counter that only discrete cards have;
  # intel_gpu_top reads the i915 perf counters instead. The module adds the
  # tool, the DRM device and CAP_PERFMON for it.
  services.beszel.agent.environment.GPU_COLLECTOR = ["intel_gpu_top"];

  # intel_gpu_top 2.x separates its JSON samples with newlines only, no
  # commas, which beszel's parser rejects; the patch accepts both.
  services.beszel.agent.package = pkgs.beszel.overrideAttrs (old: {
    patches = (old.patches or []) ++ [./beszel-intel-gpu-top-json.patch];
  });
}
