{
  apiVersion = "v1";
  kind = "Secret";
  metadata = {
    name = "opencode-server-auth";
    namespace = "opencode";
  };
  type = "Opaque";
  data.password = "Y2hhbmdlbWU="; # echo -n 'changeme' | base64
}
