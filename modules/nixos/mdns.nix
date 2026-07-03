# mDNS via avahi: publish this host as <hostname>.local and resolve other
# hosts' .local names through NSS. Used so nutmeg's *arr can reach the download
# clients on tuckles at tuckles.local without any DNS rewrites.
{ ... }:
{
  services.avahi = {
    enable = true;
    nssmdns4 = true; # resolve *.local A (IPv4) records via getaddrinfo/NSS
    nssmdns6 = true; # also resolve *.local AAAA (IPv6) records via NSS
    publish = {
      enable = true;
      addresses = true; # advertise this host's A record (<hostname>.local)
      # register a mDNS HINFO record which contains information about the local operating system and CPU
      hinfo = true;
      # Needed to allow samba to automatically register mDNS records, without the need for an `extraServiceFile`
      userServices = true;
    };
    openFirewall = true; # mDNS UDP 5353
  };
}
