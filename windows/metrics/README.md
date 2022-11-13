# Prometheus Windows Exporter setup

This guide walks you through the steps to deploy and test the Prometheus Windows Exporter on Windows nodes.

The steps below are based on the upstream Windows Exporter Kubernetes DaemonSet v0.19.0 that can be found in [this repository](https://github.com/prometheus-community/windows_exporter/tree/v0.19.0/kubernetes). This approach requires Kubernetes 1.22+, containerd 1.6 Beta+ and WindowsHostProcessContainers feature-gate for which TKG 1.6.0 qualifies. In this guide we have locked down on version `v0.19.0` of the Windows Exporter after finding [an issue](https://github.com/prometheus-community/windows_exporter/issues/1092) with `v0.20.0`.
An alternative valid approach is to use te MSI Installer to deploy the windows Exporter and launch it as a Windows Service as described [here](https://github.com/prometheus-community/windows_exporter/tree/master#installation)

The guide assumes an air-gapped environment and so images are relocated and yaml adjusted accordingly. If  your environment is not air-gapped ignore those steps.

## 1. Relocate Container Images

Relocate images: adjust the below commands accordingly to your Harbor Registry FQDN, location of Harbor Cert file and location of the docker authfile in your jumpbox.
```bash
mkdir -p ~/workspace/metrics

export SKOPEO_LOCAL_FOLDER="/home/jaime/workspace/metrics/"
export SKOPEO_AUTH_FILE="/home/jaime/.docker/config.json."
export SKOPEO_CERT_FOLDER="/tmp"
export SKOPEO_HARBOR_REGISTRY="harbor.h2o-4-1056.h2o.vmware.com"

# nanoserver:1809
skopeo copy --override-os windows docker://mcr.microsoft.com/windows/nanoserver:1809 docker-archive:${SKOPEO_LOCAL_FOLDER}nanoserver.tar
skopeo copy docker-archive:${SKOPEO_LOCAL_FOLDER}nanoserver.tar --dest-cert-dir=${SKOPEO_CERT_FOLDER} --dest-authfile=${SKOPEO_AUTH_FILE} docker://${SKOPEO_HARBOR_REGISTRY}/tkg/nanoserver:1809

# windows-exporter:0.19.0
skopeo copy --override-os windows docker://ghcr.io/prometheus-community/windows-exporter:0.19.0 docker-archive:${SKOPEO_LOCAL_FOLDER}windows-exporter.tar
skopeo copy docker-archive:${SKOPEO_LOCAL_FOLDER}windows-exporter.tar --dest-cert-dir=${SKOPEO_CERT_FOLDER} --dest-authfile=${SKOPEO_AUTH_FILE} docker://${SKOPEO_HARBOR_REGISTRY}/tkg/windows-exporter:0.19.0 
```

## 2. Deploy Daemon Set

Adjust configuration and deploy:
```bash
export CSI_NANOSERVER_IMAGE=$SKOPEO_HARBOR_REGISTRY/tkg/nanoserver:1809
export CSI_WINDOWS_EXPORTER_IMAGE=$SKOPEO_HARBOR_REGISTRY/tkg/windows-exporter:0.19.0
yq e -i 'select(.kind == "DaemonSet").spec.template.spec.initContainers[0].image = strenv(CSI_NANOSERVER_IMAGE)' ./windows/metrics/windows-exporter-daemonset.yaml
yq e -i 'select(.kind == "DaemonSet").spec.template.spec.containers[0].image = strenv(CSI_WINDOWS_EXPORTER_IMAGE)' ./windows/metrics/windows-exporter-daemonset.yaml

# Add the toleration.
#    - key: "os"
#      operator: "Equal"
#      value: "windows"
#      effect: "NoSchedule"
export CSI_WIN_TOLERATION_KEY="os"
export CSI_WIN_TOLERATION_OPERATOR="Equal"
export CSI_WIN_TOLERATION_VALUE="windows"
export CSI_WIN_TOLERATION_EFFECT="NoSchedule"
yq e -i 'select(.kind == "DaemonSet").spec.template.spec.tolerations[0].key = strenv(CSI_WIN_TOLERATION_KEY)' ./windows/metrics/windows-exporter-daemonset.yaml
yq e -i 'select(.kind == "DaemonSet").spec.template.spec.tolerations[0].operator = strenv(CSI_WIN_TOLERATION_OPERATOR)' ./windows/metrics/windows-exporter-daemonset.yaml
yq e -i 'select(.kind == "DaemonSet").spec.template.spec.tolerations[0].value = strenv(CSI_WIN_TOLERATION_VALUE)' ./windows/metrics/windows-exporter-daemonset.yaml
yq e -i 'select(.kind == "DaemonSet").spec.template.spec.tolerations[0].effect = strenv(CSI_WIN_TOLERATION_EFFECT)' ./windows/metrics/windows-exporter-daemonset.yaml

# Deploy configuration
kubectl create ns monitoring
kubectl apply -f ./windows/metrics/windows-exporter-daemonset.yaml

# Confirm pods are running
kubectl get po -n monitoring
```

## 3. Test Windows Exporter metrics

### 3.1 Test accessing the metrics endpoint directly
```bash
# Test windows exporter is publising metrics on port 9182
kubectl get no -owide
# Check the /metrics endpoint of any windows node
curl -v http://<windows-node-ip>:9182/metrics
```

### 3.2 Test scraping metrics from Prometheus Server


Assuming you have a Prometheus Server available you can add a simple `scrape_config` job to the Prometheus Server configuration to collect the metrics exposed on the Windows Exporter of every Windows node. Example:
```bash
    - job_name: 'windows-node-exporter'
      metrics_path: /metrics
      static_configs:
      - targets:
        - '10.220.52.46:9182'
        - '10.220.52.51:9182'
```

If your Prometheus Server has been deployed with the Prometheus TKG Package, then you need to create an overlay to annotate the PackageInstall with it. We have included a sample `.windows/metrics/prometheus-overlay.yaml` in this repo that you can use for that. Replace the IPs in lines 34 and 35 in that yaml file with the IPs of your Windows Nodes (add all of them). Then you can run the following commands:
```bash
# Change context to the Linux cluster where you have the Prometheus Server
kubectl config use-context lin1-admin@lin1
# Change directory to the local foler of the Prometheus Overlay
cd .windows/metrics/
# Create Secret with the Overlay yaml
kubectl create secret generic prometheus-overlay --from-file=prometheus-overlay.yaml -n tanzu-user-managed-packages
# Annotate the Prometheus Pakcage with the overlay config
kubectl annotate PackageInstall prometheus ext.packaging.carvel.dev/ytt-paths-from-secret-name.0=prometheus-overlay -n tanzu-user-managed-packages
# This should force the Package to reconcyle and start scraping the Windows exporter metrics endpoints
```

Test the metrics are there:
- If you have Grafana connected to the Prometheus Server you should find the metrics already available. Query for any `windows*` metric.
- Alternatively you can check directly via the Prometheus UI. Either exposing the `prometheus-server` Service (NodePort or LoadBalancer) or via proxy server. Here's a screenshot of how the metrics queried from the Prometheus Server UI: ![prometheus-metrics-ui](/windows/metrics/prometheus-metrics-ui.png)

