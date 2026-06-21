# mDNS via avahi: publish this host as <hostname>.local and resolve other
# hosts' .local names through NSS. Used so nutmeg's *arr can reach the download
# clients on tuckles at tuckles.local without any DNS rewrites.
{ ... }:
{
  services.avahi = {
    enable = true;
    nssmdns4 = true; # resolve *.local via getaddrinfo/NSS
    publish = {
      enable = true;
      addresses = true; # advertise this host's A record (<hostname>.local)
    };
    openFirewall = true; # mDNS UDP 5353
  };
}
