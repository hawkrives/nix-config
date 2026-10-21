{...}: {
  # TRAWL — a scraping service that gets past Cloudflare-style challenges.
  # Prowlarr's tagged indexers (1337x) use its MITM forward proxy on
  # 127.0.0.1:8192. The FlareSolverr-compatible API on 8191 isn't enough there:
  # Prowlarr keeps only the cf_clearance cookie and user agent and re-fetches
  # with its own HTTP client, whose TLS fingerprint Cloudflare challenges again.
  # Through the forward proxy, TRAWL makes the request itself and escalates to a
  # browser when challenged.
  #
  # Neither listener has authentication or a bind setting that helps under host
  # networking, so this runs on a bridge network and publishes loopback only.
  virtualisation.oci-containers.containers.trawl = {
    # Image is pinned by digest. Renovate bumps the tag and digest together (see
    # the customManagers entry in renovate.json5); by hand, resolve the digest
    # with `skopeo inspect --format '{{.Digest}}' docker://<image>`. The
    # -baseline variant is required: nutmeg's Ivy Bridge CPU has no AVX2.
    # renovate: datasource=docker depName=ghcr.io/germondai/trawl versioning=regex:^(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)-baseline$
    image = "ghcr.io/germondai/trawl:1.9.2-baseline@sha256:51c8554d9da8833045ce1c35c852c817c99ec13f22d3c086ef2604b389a510c4";
    autoStart = true;
    ports = [
      "127.0.0.1:8191:8191" # API
      "127.0.0.1:8192:8192" # MITM forward proxy
    ];
    environment = {
      SESSION_CACHE_DRIVER = "memory";
      BROWSER_POOL_SIZE = "1";
      MITM_ENABLED = "true";
      # Tier 4 is the residential-proxy tier; none is configured.
      MITM_MAX_TIER = "3";
    };
    # The MITM root CA and its private key. Persisted so the CA Prowlarr trusts
    # survives container recreation.
    volumes = ["/var/lib/trawl/proxy-ca:/data/proxy-ca"];
    extraOptions = [
      "--shm-size=1gb"
      "--pull=missing" # digest-pinned; upgrades are a deliberate Renovate PR
    ];
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/trawl 0700 root root - -"
    "d /var/lib/trawl/proxy-ca 0700 root root - -"
  ];

  # Trust for the MITM CA is scoped to Prowlarr: rather than adding it to
  # security.pki (which every process on the host trusts), build a bundle of the
  # system roots plus the TRAWL CA and point only Prowlarr's SSL_CERT_FILE at it.
  # .NET on Linux reads its root store through OpenSSL, which honours that
  # variable. Without ca.crt the bundle is the system roots alone, so Prowlarr's
  # other HTTPS keeps working and only proxied indexers fail.
  systemd.services.trawl-prowlarr-ca = {
    description = "CA bundle for Prowlarr: system roots + TRAWL MITM CA";
    after = ["podman-trawl.service"];
    wants = ["podman-trawl.service"];
    before = ["prowlarr.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      RuntimeDirectory = "trawl-ca";
      RuntimeDirectoryMode = "0755";
    };
    script = ''
      ca=/var/lib/trawl/proxy-ca/ca.crt
      # TRAWL writes its CA on first start; give a fresh container time to.
      for _ in $(seq 1 30); do [ -s "$ca" ] && break; sleep 2; done
      out=/run/trawl-ca/prowlarr-bundle.pem
      cat /etc/ssl/certs/ca-certificates.crt > "$out.tmp"
      if [ -s "$ca" ]; then
        cat "$ca" >> "$out.tmp"
      else
        echo "no $ca; bundle has system roots only" >&2
      fi
      chmod 0444 "$out.tmp"
      mv "$out.tmp" "$out"
    '';
  };

  systemd.services.prowlarr = {
    wants = ["trawl-prowlarr-ca.service"];
    after = ["trawl-prowlarr-ca.service"];
    environment.SSL_CERT_FILE = "/run/trawl-ca/prowlarr-bundle.pem";
  };
}
