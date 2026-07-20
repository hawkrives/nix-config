{...}: {
  # Linux audit is off on the host-server fleet. A write-only local audit log
  # that nothing ships or reviews gives little detection/forensic value while
  # churning SSD writes, so we don't run it.
  security.auditd.enable = false;
  security.audit.enable = false;
}
