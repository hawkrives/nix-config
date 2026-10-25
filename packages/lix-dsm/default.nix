# Lix 2.96 patched to run on potato-bunny, the Synology NAS.
#
# DSM 7.4 ships Linux 4.4, which lacks three things stock Lix assumes:
#
# - SO_PEERGROUPS (Linux 4.13+). The daemon asks for every client's
#   supplementary groups and rejects the connection outright on ENOPROTOOPT.
#   Patched to carry on without them; the only loss is `@group` entries in
#   trusted-users/allowed-users.
# - seccomp. Synology builds the kernel without it, so loading the builder's
#   syscall filter fails with ENOSYS and every build dies. Lix has no
#   filter-syscalls setting to turn it off. Patched to build unfiltered there.
# - cgroup namespaces (Linux 4.6+). Sandbox setup unshares one and gets
#   EINVAL. Patched to sandbox without it; the mount/pid/net/ipc/uts
#   namespaces are unaffected.
#
# Each hunk only tolerates the specific errno an old kernel returns, so on a
# modern kernel this behaves exactly like stock Lix.
#
# Not in cache.nixos.org: nutmeg builds it and pushes it to the fleet cache. Tests are
# skipped because the functional suite needs kernel features unrelated to the
# patch and roughly doubles the build time.
{pkgs, ...}:
pkgs.lixPackageSets.lix_2_96.lix.overrideAttrs (old: {
  patches = (old.patches or []) ++ [./lix-old-kernel.patch];
  doCheck = false;
  doInstallCheck = false;
  meta = old.meta // {platforms = ["x86_64-linux"];};
})
