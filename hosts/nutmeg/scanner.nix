{ pkgs, ... }:
{
  # Epson ET-3958, reached over eSCL/AirScan. sane-airscan speaks eSCL over
  # HTTPS, so no USB, no udev rules, and no proprietary Epson driver is needed.
  # The device is addressed by its mDNS name rather than a DHCP lease.
  hardware.sane = {
    enable = true;
    extraBackends = [ pkgs.sane-airscan ];
  };
}
