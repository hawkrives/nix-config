# DSM features `dsm.services.<name>` knows by name: the Package Center id
# that provides each, and the web API holding its settings. Any other name
# works too, given `package` and/or `settingsApi` explicitly.
{
  container-manager.package = "ContainerManager";
  tailscale.package = "Tailscale";
  smb = {
    package = "SMBService";
    settingsApi = {
      api = "SYNO.Core.FileServ.SMB";
      version = 3;
    };
  };
  # Built into DSM: no package, so `enable` is only the enable_ssh setting.
  ssh.settingsApi = {
    api = "SYNO.Core.Terminal";
    version = 3;
  };
}
