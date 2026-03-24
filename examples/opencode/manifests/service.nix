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
    ports = [{
      name = "http";
      port = 4096;
      targetPort = "http";
      protocol = "TCP";
    }];
    type = "ClusterIP";
  };
}
