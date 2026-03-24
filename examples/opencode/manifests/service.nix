{
  apiVersion = "v1";
  kind = "Service";
  metadata = {
    name = "opencode-server";
    namespace = "opencode";
    labels.app = "opencode-server";
  };
  spec = {
    selector.app = "opencode-server";
    ports = [
      {
        name = "opencode";
        port = 4096;
        targetPort = "opencode";
        protocol = "TCP";
      }
      {
        name = "api";
        port = 3000;
        targetPort = "api";
        protocol = "TCP";
      }
    ];
    type = "ClusterIP";
  };
}
