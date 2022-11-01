# Windows Containers advanced

This guide is focused on the Platform Operator persona that owns and has admin access to a Tanzu Kubernetes Grid environment on vSphere. This guide will help the Platform Operator to create a Windows base image, use it to create a TKG cluster with (short-named) Windows nodes, and deploy CSI Drivers(s) in it; all in an environment without internet connectivity (a.k.a air-gapped).

## 0. Pre-requisites

This Guides makes a few assumptions on the environment and tools available for the user.
- Existing vSphere v7.0.x environment without interenet connectivity in the default networks.
- Existing Linux jumpbox with internet connectivity, direct via special network interface or via proxy, with the following CLIs installed: Tanzu CLI v1.6.0 with all the Carvel tools included in the package, yq, kubeclt, and Docker Engine. Here's [a sample guide](https://github.com/Tanzu-Solutions-Engineering/tanzu-workstation-setup/blob/main/Linux.md) that can help with that setup.
- Existing Standalone Harbor Registry in place in the same environment, or accessible from the environment. Here's [a sample guide](https://github.com/Tanzu-Solutions-Engineering/tanzu-workstation-setup/blob/main/Harbor.md) that can help with that setup.
- Harbor Registry will have a Public `tkg` project.
- Harbor CA cert stored in a local path in your jumpbox. In this guide it will be here: `~/data/ca.crt`.
- Existing Tanzu Kubernetes Grid v1.6.0 management cluster deployed on networks without internet access. Here is the [Official Documentation](https://docs.vmware.com/en/VMware-Tanzu-Kubernetes-Grid/1.6/vmware-tanzu-kubernetes-grid-16/GUID-mgmt-clusters-airgapped-environments.html) that can guide you to prepare that setup.

## 1. Create Windows Image

This guide follows some of the steps of the official doc for building windows images [here](https://docs.vmware.com/en/VMware-Tanzu-Kubernetes-Grid/1.6/vmware-tanzu-kubernetes-grid-16/GUID-build-images-windows.html), adapting them to air-gapped.

### 1.1 Populate additional images

Assuming an environment without internet connectivity: in addition to the TKG system and services images that you have relocacted already as part of the initial setup and TKG mangement cluster deployment, we need to relocate a few other Windows images

Relocate servercore container, and Image Builder container images. Replace local paths and destination registry URLs accordingly.
```bash
imgpkg copy -i mcr.microsoft.com/windows/servercore:ltsc2019 --to-repo harbor.h2o-4-1056.h2o.vmware.com/tkg/servercore --registry-ca-cert-path /tmp/cacrtbase64d.crt --include-non-distributable-layers
imgpkg copy -i projects.registry.vmware.com/tkg/image-builder:v0.1.12_vmware.2 --to-repo harbor.h2o-4-1056.h2o.vmware.com/tkg/image-builder --registry-ca-cert-path /tmp/cacrtbase64d.crt

## For test apps
## Using the skopeo commands (need installing skopeo binary: https://github.com/containers/skopeo) which enusres all layers of the image are copied to the registry
skopeo copy --override-os windows --override-arch multiarch docker://mcr.microsoft.com/dotnet/framework/samples:aspnetapp-windowsservercore-ltsc2019 docker-archive:/home/jaime/workspace/tanzu-poc/k8s/aspnet/aspnet.tar
skopeo copy docker-archive:/home/jaime/workspace/tanzu-poc/k8s/aspnet/aspnet.tar --dest-cert-dir="/tmp/" --dest-authfile="/home/jaime/.docker/config.json." docker://harbor.h2o-4-1056.h2o.vmware.com/tkg/aspnet:aspnetapp-windowsservercore-ltsc2019
# This would be the equivalent command with imgpkg but had some issues with it and that specific Windows Container image.
# imgpkg copy -i mcr.microsoft.com/dotnet/framework/samples:aspnetapp-windowsservercore-ltsc2019 --to-repo harbor.h2o-4-1056.h2o.vmware.com/tkg/aspnet --registry-ca-cert-path /tmp/cacrtbase64d.crt --include-non-distributable-layers
```

### 1.2 Image Builder pre-requisites

1. You must obtain a Windows Server 2019 iso image, with the latest patch version August 2021 or later. You need to upload the iso file to your datastore’s [ISO] folder, noting the uploaded path.
2. Download the latest VMware Tools iso image from https://packages.vmware.com/tools/releases/latest/windows/VMware-tools-windows-12.1.0-20219665.iso) and upload to your datastore’s [ISO] folder, noting the uploaded path.

### 1.3 Deploy Image Builder Resource Kit

Change context to your management cluster (edit command for the right context name) and apply the `/windows/image/builder-airgapped.yaml` file included in this repo.

Make sure to edit the yaml to change the Harbor registry domain of the image to the one you are using. This is where you re-located the images before deploying the management cluster.

```bash
kubectl config use-context mgmt-admin@mgmt
kubectl apply -f ./windows/image/builder-airgapped.yaml
# check pods are Running
kubectl get pods -n imagebuilder
```

### 1.4 Prepare web server with CSI Proxy Binary

You need to build the CSI Proxy Binary as described in the upstream [CSI Proxy Build guide](https://github.com/kubernetes-csi/csi-proxy/tree/v1.1.1#build). In this guide we have used `v1.1.1` of the CSI Proxy.

Once you have built the `csi-proxy.exe` binary you must upload it to the jumpbox from where you are operating in this guide. Then we will setup a web server to make this binary available during the Image Builder process.

```bash
# change directory to a suitable spot in your jumpbox (~/workspace/ in this guide)
mkdir -p ~/workspace/winres
# copy the csi-proxy.exe binary to that location
cd ~/workspace/
set -m; nohup python3 -m http.server --directory winres > /dev/null 2>&1 & 
# Test your Jumpbox IP on port 8000 in your browser to confirm files are available and ready to be served. Example:
# http://10.220.52.10:8000
```

### 1.5 Create Configuration for Windows Image

Edit the `/windows/image/windows-airgapped.json` sample file in this repo and change the following fields:
- unattend_timezone: < your vcenter environment timezone> # hint: use `tzutil /l` on Windows to get a list of the supported timezone values, or check https://www.windowsafg.com/win10x86_x64_uefi.html
- password: < your vCenter password >
- username: < your vCenter username >
- datastore: < your vCenter datastore >
- datacenter: < your vCenter datacenter >
- vmtools_iso_path < your datastore iso path and vmware-tools iso name you uploaded earlier in this guide >
- network: < a vCenter portgroup/network available >
- os_iso_path: < your datastore iso path and windows-image iso name you uploaded earlier in this guide >
- vcenter_server: < your vCenter IP or FQDN >
- kubernetes_base_url, containerd_url, additional_executables_list, nssm_url, wins_url, cloudbase_init_url, ssh_source_url, goss_url: < change IP to the IP of one of the Control Plane nodes in your management cluster >
- windows_updates_categories: < make sure this is empty since windows updates need to be ignored in this airgapped image-builder steps >
- pause_image: < your internal registry pause image, which you relocated together with all TKG system images >
- debug_tools: < make sure it is set to false >
- additional_executables_list: to incldue the csi-proxy.exe in the Image place here the internal URL of the web server you launched in the previous step (comma separated). E.g, add `,http://10.220.52.10:8000/csi-proxy.exe`

Check the `/windows/image/autounattend.xml` file in this repo:
- You may need to review the `ProductKey` and drive allocations match your requirements in your environment, especially if this template is built for a production environment that requires specific MAK keys. Remember the password in this file is temporary and will be removed prior to pushing the image into vSphere.

### 1.6 Create Windows Image

Run this command from the `/windows/image/` folder that contains the `windows-airgapped.json` and `autounattend.xml` you worked on the previous step. Adjust the `image-builder` container image URI to match with your Harbor registry.

```bash
docker run -it --rm --mount type=bind,source=$(pwd)/windows-airgapped.json,target=/windows.json --mount type=bind,source=$(pwd)/autounattend.xml,target=/home/imagebuilder/packer/ova/windows/windows-2019/autounattend.xml -e PACKER_VAR_FILES="/windows.json" -e IB_OVFTOOL=1 -e IB_OVFTOOL_ARGS='--skipManifestCheck' -e PACKER_FLAGS='-force -on-error=ask' -e PACKER_LOG=1 -t harbor.h2o-4-1056.h2o.vmware.com/tkg/image-builder:v0.1.12_vmware.2 build-node-ova-vsphere-windows-2019
```

This process will take ~30 minutes: as it creates A VM in your vSphere environment, reboots it a few times and finally creates a vSphere VM Template out of it.


## 2. Create a TKG cluster with Windows nodes

### 2.1 Configure Registry Endpoint and Certs

Configure persistent Private Registry settings in the Tanzu CLI. This should have been done already during the deployment of the management cluster, but just to be sure we reiterate it.

```bash
# Replace these values with your Harbor FQDN/project and location of the Harbor CA cert respectively.
export TKG_CUSTOM_IMAGE_REPOSITORY="harbor.h2o-4-1056.h2o.vmware.com/tkg"
export TKG_CUSTOM_IMAGE_REPOSITORY_CA_CERTIFICATE=`base64 -w 0 ~/data/ca.crt`
# CLI settings
tanzu config set env.TKG_CUSTOM_IMAGE_REPOSITORY $TKG_CUSTOM_IMAGE_REPOSITORY
tanzu config set env.TKG_CUSTOM_IMAGE_REPOSITORY_SKIP_TLS_VERIFY false
tanzu config set env.TKG_CUSTOM_IMAGE_REPOSITORY_CA_CERTIFICATE $TKG_CUSTOM_IMAGE_REPOSITORY_CA_CERTIFICATE
```

For Windows clusters you also need to inject the CA Cert via Ovelay. See below.

### 2.2 Prepare Cluster customizations

To change the CP taint that prevents deploying pods into CP nodes, copy the `/windows/overlays/remove-cp-taints-overlay.yaml` and `/windows/overlays/remove-cp-taints-values.yaml` files into the `~/.config/tanzu/tkg/providers/ytt/03_customizations` folder.

If you want to configure the Windows node names to have 15 characters or less you should copy `/windows/overlays/windows-0shortnodenames-overlay.yaml` and `/windows/overlays/windows-0shortnodenames-values.yaml` files into the `~/.config/tanzu/tkg/providers/ytt/03_customizations` folder. This would facilitate deploying certain TKG add-ons and the integration with TMC.

If you are deploying Windows Clusters and using a Harbor registry wih self-signed certs you will also need to inject the CA Cert via Ovelay. Copy the `/windows/overlays/windows-inject-cert.yaml` and the `/windows/overlays/windows-inject-cert-values.yaml` into the `~/.config/tanzu/tkg/providers/ytt/03_customizations` folder.

To start the CSI Proxy as a Windows service in the Windows nodes you need to edit the `~/.config/tanzu/tkg/providers/infrastructure-vsphere/v1.3.1/ytt/overlay-windows.yaml` file:
```bash
# Add the following code after row 408 (after the Start Services block). include 10 spaces at the beginning of each row for the right indentation

# Configure and Start CSI Proxy
$csiflags = "-windows-service -log_file=C:\programdata\temp\csi-proxy.log -logtostderr=false"
sc.exe create csiproxy binPath= "C:\programdata\temp\csi-proxy.exe $csiflags" start= auto
sc.exe failure csiproxy reset= 0 actions= restart/10000
sc.exe start csiproxy
```

### 2.3 Prepare Windows Cluster config file

Copy the `cluster-config.yaml` you used to deploy the management-cluster into a new `win1-cluster-config.yaml` file, then make some edits in it:
- Delete `AVI` keys, except `AVI_CONTROL_PLANE_HA_PROVIDER`
- Delete `ENABLE_CEIP_PARTICIPATION`
- Delete `LDAP` keys
- Delete `OIDC` keys
- Delete `DEPLOY_TKG_ON_VSPHERE7` and `ENABLE_TKGS_ON_VSPHERE7` (if present)
- Update the following properties to these default values (at least)
```bash
VSPHERE_WORKER_DISK_GIB: "50"
VSPHERE_WORKER_MEM_MIB: "16384"
VSPHERE_WORKER_NUM_CPUS: "4"
VSPHERE_CONTROL_PLANE_DISK_GIB: "40"
VSPHERE_CONTROL_PLANE_MEM_MIB: "16384"
VSPHERE_CONTROL_PLANE_NUM_CPUS: "4"
OS_NAME: ubuntu
OS_VERSION: 2004
ENABLE_MHC: false
```
- Update `CLUSTER_NAME` with a suitable name for your Windows Cluster. In this guide we use `win1`
- Update `VSPHERE_CONTROL_PLANE_ENDPOINT` to one of the NSX-ALB (AVI) VIPs avaiable in the pool or leave empty for it to be auto-asigned
- Add `WORKER_MACHINE_COUNT` with the number of worker nodes you want for the Windows cluster
- Add `ROOT_CERT` with the base64 encoded CA cert for your Harbor registry
- Add the following properties
```bash
IS_WINDOWS_WORKLOAD_CLUSTER: "true"
VSPHERE_WINDOWS_TEMPLATE: windows-2019-kube-v1.23.8
REMOVE_CP_TAINT: "true"
```

### 2.4 Deploy Windows Cluster

Move to the folder where you created the `win1-cluster-config.yaml` file.

If you want to deploy a Windows cluster ensuring the shortest node name (cluster-name+6_char_hash) then use this script call, chainging the last parameter to the number of worker nodes you desire:
```bash
# Edit worker nodes in your cluster config to 0 and set flag to true
WORKER_MACHINE_COUNT: 0
ZERO_SHORT_NODE_NAMES: "true"

# Deploy with this script. The third parameter is the actal number of nodes you want to have
/windows/create_windows_cluster_shortnodename.sh "win1" "win1-cluster-config.yaml" 2
```

Otherwise follow these steps:
```bash
# Deploy
tanzu cluster create -f win1-cluster-config.yaml -v 6
# get some more coffee, takes about 15 minutes
```

Validate admin access to windows cluster
```bash
tanzu cluster kubeconfig get win1 --admin
kubectl config use-context win1-admin@win1
k get po -A
```

## 3. Deploy SMB CSI Driver

Follow the [SMB CSI Driver setup guide](/smb-csi/README.md)