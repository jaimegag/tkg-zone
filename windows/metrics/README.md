# Prometheus Windows Exporter setup

This guide walks you through the steps to deploy and test the Prometheus Windows Exporter on Windows nodes.

The steps below are based on the upstream Windows Exporter Kubernetes DaemonSet v0.22.0 that can be found in [this repository](https://github.com/prometheus-community/windows_exporter/tree/v0.22.0/kubernetes). This approach requires Kubernetes 1.22+, containerd 1.6 Beta+ and WindowsHostProcessContainers feature-gate for which TKG 2.1 qualifies.
An alternative valid approach is to use te MSI Installer to deploy the windows Exporter and launch it as a Windows Service as described [here](https://github.com/prometheus-community/windows_exporter/tree/master#installation)

The guide assumes an air-gapped environment and so images are relocated and yaml adjusted accordingly. If  your environment is not air-gapped ignore those steps.

## 1. Relocate Container Images

For simplicity we will reuse the existing `tkg` project in the Harbor registry.

Relocate images: adjust the below commands accordingly to your Harbor Registry FQDN, location of Harbor Cert file and location of the docker authfile in your jumpbox.
```bash
mkdir -p ~/workspace/metrics

export REPO_LOCAL_FOLDER="/home/jaime/workspace/csi/"
export REPO_AUTH_FILE="/home/jaime/.docker/config.json"
export REPO_CERT_FOLDER="/home/jaime/workspace/"
export REPO_HARBOR_REGISTRY="harbor.h2o-4-1056.h2o.vmware.com"

# nanoserver:1809
skopeo copy --override-os windows docker://mcr.microsoft.com/windows/nanoserver:1809 docker-archive:${REPO_LOCAL_FOLDER}nanoserver.tar
skopeo copy docker-archive:${REPO_LOCAL_FOLDER}nanoserver.tar --dest-cert-dir=${REPO_CERT_FOLDER} --dest-authfile=${REPO_AUTH_FILE} docker://${REPO_HARBOR_REGISTRY}/tkg/nanoserver:1809

# windows-exporter:0.22.0
skopeo copy --override-os windows docker://ghcr.io/prometheus-community/windows-exporter:0.22.0 docker-archive:${REPO_LOCAL_FOLDER}windows-exporter.tar
skopeo copy docker-archive:${REPO_LOCAL_FOLDER}windows-exporter.tar --dest-cert-dir=${REPO_CERT_FOLDER} --dest-authfile=${REPO_AUTH_FILE} docker://${REPO_HARBOR_REGISTRY}/tkg/windows-exporter:0.22.0 
```

## 2. Deploy local Prometheus Server

This is a recommendad step to be followed if you want to scrape the Windows metrics later from a local Promethus server running in the same cluster. This allows you to also collect all other metrics from control-plane nodes and k8s API. But if you just need to scrape Windows metrics from an external Promethus server you can ignore this step.

In addition to deploy the Prometheus Server we need the vSpehre CSI Driver, and luckily for us we should have it already installed on a TKG 2.1.x Windows or MultiOS cluster, in the linux nodes

### 2.2 Deploy Prometheus Package

We will deploy the Prometheus Package that is distributed with TKG to ensure supportability of these bits.

Follow these steps
```bash
# Go to the /windows/metrics folder in this repo
cd ~/workspace/tkg-zone/windows/metrics
# Prepare Tanzu Standard Package repository (if you haven't already)
kubectl create ns tanzu-user-managed-packages
tanzu package repository add tanzu-standard --url $REPO_HARBOR_REGISTRY/tkg/packages/standard/repo:v2.2.0 -n tanzu-user-managed-packages
# Deploy Package using the prometheus-values.yaml included in this location of the repo. This will expose the Prometheus Server service as Load Balancer (this is optional)
tanzu package install prometheus --package prometheus.tanzu.vmware.com --version 2.37.0+vmware.3-tkg.1 --namespace tanzu-user-managed-packages --values-file prometheus-values.yaml --ytt-overlay-file prometheus-overlay.yaml
# Confirm reconsiliation succeeds by checking with this command, and look for 
#      STATUS:                  Reconcile succeeded
tanzu package installed get prometheus -n tanzu-user-managed-packages
# Get the LoadBalancer IP of the Prometheus server
kubectl get svc prometheus-server -n tanzu-system-monitoring
```

## 3. Deploy Windows Exporter Daemon Set

We will use a Daemon Set with two changes over the [upsteam version](https://github.com/prometheus-community/windows_exporter/blob/v0.22.0/kubernetes/windows-exporter-daemonset.yaml) of the yaml:
- Added Prometheus annotations to the `spec.template` to allow a local Promethus to automatically scrape metrics from the DameonSet Pods

You can also remove/disable the `hostPort` setting if you are going to scrap the windows exporter metrics endpoints from within the same cluster (see section [4.2](/windows/metrics/README.md#42-test-scraping-metrics-from-local-prometheus-server) below).

Adjust configuration and deploy:
```bash
export NANOSERVER_IMAGE=$REPO_HARBOR_REGISTRY/tkg/nanoserver:1809
export WINDOWS_EXPORTER_IMAGE=$REPO_HARBOR_REGISTRY/tkg/windows-exporter:0.22.0
yq e -i 'select(.kind == "DaemonSet").spec.template.spec.initContainers[0].image = strenv(NANOSERVER_IMAGE)' ./windows-exporter-daemonset.yaml
yq e -i 'select(.kind == "DaemonSet").spec.template.spec.containers[0].image = strenv(WINDOWS_EXPORTER_IMAGE)' ./windows-exporter-daemonset.yaml

# Add the toleration.
#    - key: "os"
#      operator: "Equal"
#      value: "windows"
#      effect: "NoSchedule"
export WIN_TOLERATION_KEY="os"
export WIN_TOLERATION_OPERATOR="Equal"
export WIN_TOLERATION_VALUE="windows"
export WIN_TOLERATION_EFFECT="NoSchedule"
yq e -i 'select(.kind == "DaemonSet").spec.template.spec.tolerations[0].key = strenv(WIN_TOLERATION_KEY)' ./windows-exporter-daemonset.yaml
yq e -i 'select(.kind == "DaemonSet").spec.template.spec.tolerations[0].operator = strenv(WIN_TOLERATION_OPERATOR)' ./windows-exporter-daemonset.yaml
yq e -i 'select(.kind == "DaemonSet").spec.template.spec.tolerations[0].value = strenv(WIN_TOLERATION_VALUE)' ./windows-exporter-daemonset.yaml
yq e -i 'select(.kind == "DaemonSet").spec.template.spec.tolerations[0].effect = strenv(WIN_TOLERATION_EFFECT)' ./windows-exporter-daemonset.yaml

# Deploy configuration
kubectl create ns monitoring
kubectl apply -f ./windows-exporter-daemonset.yaml

# Confirm pods are running
kubectl get po -n monitoring
```

## 4. Use Windows Exporter metrics

### 4.1 Test accessing the metrics endpoint directly

This will only work if you kept the `hostPort` setting in the DaemonSet config.

```bash
# Test windows exporter is publising metrics on port 9182
kubectl get no -owide
# Check the /metrics endpoint of any windows node
curl -v http://<windows-node-ip>:9182/metrics
```

### 4.2 Test scraping metrics from local Prometheus server

Since we annotated the Winows Exporter pods to enable prometheus scraping we don't have to do any further configuration:

Access the Prometheus Server LoadBalancer IP you obtained in [step 2.2](/windows/metrics/README.md#22-deploy-prometheus-package) of this guide.

Navigate to the `Status > Targets` view using the top menu bar.

Scroll down to the `kubernetes-pods` section. You should be able to see one Endpoint per every single node you have in the cluster. Linux (control-plane) nodes on port `9100` and Windows nodes on port `9182`.
It should look like this:
![prometheus-targets](/windows/metrics/prometheus-targets.png)

Go to `Graph` view. You should be able to query for either linux control-plane node metrics, windows node metrics or other k8s metrics.
![prometheus-query](/windows/metrics/prometheus-query.png)

### 4.3 Test scraping metrics from external Prometheus Server

Assuming you have an external (to this cluster) Prometheus Server available you can add a simple `scrape_config` job to the Prometheus Server configuration to collect the metrics exposed on the Windows Exporter of every Windows node. Example:
```bash
    - job_name: 'windows-node-exporter'
      metrics_path: /metrics
      static_configs:
      - targets:
        - '10.220.52.46:9182'
        - '10.220.52.51:9182'
```

If your Prometheus Server has been deployed with the Prometheus TKG Package, then you need to create an overlay to annotate the PackageInstall with it. We have included a sample `.windows/metrics/prometheus-overlay-external.yaml` in this repo that you can use for that. Replace the IPs in lines 34 and 35 in that yaml file with the IPs of your Windows Nodes (add all of them). Then you can run the following commands:
```bash
# Change context to the Linux cluster where you have the Prometheus Server
kubectl config use-context lin-admin@lin
# Change directory to the local foler of the Prometheus Overlay
cd .windows/metrics/
# Create Secret with the Overlay yaml
kubectl create secret generic prometheus-overlay-external --from-file=prometheus-overlay-external.yaml -n tanzu-user-managed-packages
# Annotate the Prometheus Pakcage with the overlay config
kubectl annotate PackageInstall prometheus ext.packaging.carvel.dev/ytt-paths-from-secret-name.0=prometheus-overlay-external -n tanzu-user-managed-packages
# This should force the Package to reconcyle and start scraping the Windows exporter metrics endpoints
```

Test the metrics are there:
- If you have Grafana connected to the Prometheus Server you should find the metrics already available. Query for any `windows*` metric.
- Alternatively you can check directly via the Prometheus UI. Either exposing the `prometheus-server` Service (NodePort or LoadBalancer) or via proxy server. Here's a screenshot of how the metrics queried from the Prometheus Server UI: ![prometheus-metrics-ui](/windows/metrics/prometheus-metrics-ui.png)

