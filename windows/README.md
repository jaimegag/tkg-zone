# Windows Containers advanced

This guide is focused on the Platform Operator persona that owns and has admin access to a Tanzu Kubernetes Grid environment on vSphere. This guide will help the Platform Operator create a Windows base image, use it to create a TKG MultiOS cluster with Windows nodes, deploy the SMB CSI Drivers in it, deploy the Prometheus Windows Exporter and deploy Fluent-Bit as well; all in an environment without internet connectivity (a.k.a air-gapped).

## 0. Pre-requisites

This Guides makes a few assumptions on the environment and tools available for the user.
- Existing vSphere v7.0.x environment without interenet connectivity in the default networks.
- Existing Linux jumpbox with internet connectivity, direct via special network interface or via proxy, with the following CLIs installed: Tanzu CLI for TKG v2.3.0 with all the Carvel tools included in the package, yq, kubeclt, and Docker Engine. Here's [a sample guide](https://github.com/Tanzu-Solutions-Engineering/tanzu-workstation-setup/blob/main/Linux.md) that can help with that setup.
- Existing Standalone Harbor Registry in place in the same environment, or accessible from the environment. You can follow instructions to Deploy a [Harbor OVA Image](https://docs.vmware.com/en/VMware-Tanzu-Kubernetes-Grid/2.3/tkg-deploy-mc/mgmt-reqs-harbor.html) in the official documentation.
- Harbor Registry will have a Public `tkg` project.
- Harbor CA cert stored in a local path in your jumpbox. In this guide it will be here: `~/workspace/harbor-cacrt.crt`.
- Existing Tanzu Kubernetes Grid v2.3.0 management cluster deployed on networks without internet access. Here is the [Official Documentation](https://docs.vmware.com/en/VMware-Tanzu-Kubernetes-Grid/2.3/tkg-deploy-mc/mgmt-reqs-prep-offline.html) that can guide you to prepare that setup.

Set folders and the following environment variables in your linux jumpbox, as we will use these a few times during the following steps:
```bash
## Create workspace folder
mkdir -p ~/workspace/
#
# Place your Harbor CA cert in that workspace folder in file harbor-cacrt.crt
#
# Clone this repository in the workspace folder -> ~/workspace/tkg-zone/
#
# Replace these values with your Harbor FQDN/project and location of the Harbor CA cert respectively.
export TKG_CUSTOM_IMAGE_REPOSITORY="harbor.h2o-4-14873.h2o.vmware.com/tkg"
export TKG_CUSTOM_IMAGE_REPOSITORY_CA_CERTIFICATE=`base64 -w 0 ~/workspace/harbor-cacrt.crt`
# Configure persistent Private Registry settings in the Tanzu CLI
tanzu config set env.TKG_CUSTOM_IMAGE_REPOSITORY $TKG_CUSTOM_IMAGE_REPOSITORY
tanzu config set env.TKG_CUSTOM_IMAGE_REPOSITORY_SKIP_TLS_VERIFY false
tanzu config set env.TKG_CUSTOM_IMAGE_REPOSITORY_CA_CERTIFICATE $TKG_CUSTOM_IMAGE_REPOSITORY_CA_CERTIFICATE
```

## 1. Create Windows Image

This guide follows some of the steps of the official doc for building windows images [here](https://docs.vmware.com/en/VMware-Tanzu-Kubernetes-Grid/2.3/tkg-deploy-mc/mgmt-byoi-windows.html), adapting them to air-gapped.

### 1.1 Populate additional images

Assuming an environment without internet connectivity: in addition to the TKG system and services images that you have relocacted already as part of the initial setup and TKG mangement cluster deployment, we need to relocate a few other Windows images

Relocate servercore container image. Replace local paths and destination registry URLs accordingly.
```bash
imgpkg copy -i mcr.microsoft.com/windows/servercore:ltsc2019 --to-tar /tmp/servercore.tar --include-non-distributable-layers
imgpkg copy --tar /tmp/servercore.tar --to-repo $TKG_CUSTOM_IMAGE_REPOSITORY/servercore --registry-ca-cert-path ~/workspace/harbor-cacrt.crt --include-non-distributable-layers

## For test apps
## Using the skopeo commands (need installing skopeo binary: https://github.com/containers/skopeo) which enusres all layers of the image are copied to the registry
skopeo copy --override-os windows --override-arch multiarch docker://mcr.microsoft.com/dotnet/framework/samples:aspnetapp-windowsservercore-ltsc2019 docker-archive:/tmp/aspnet-skopeo.tar
skopeo copy docker-archive:/tmp/aspnet-skopeo.tar --dest-cert-dir="/home/jaime/workspace/" --dest-authfile="/home/jaime/.docker/config.json" docker://harbor.h2o-4-14873.h2o.vmware.com/tkg/aspnet-skopeo:aspnetapp-windowsservercore-ltsc2019
# These would be the equivalent commands with imgpkg but had some issues with it and that specific Windows Container image.
#imgpkg copy -i mcr.microsoft.com/dotnet/framework/samples:aspnetapp-windowsservercore-ltsc2019 --to-tar /tmp/aspnet.tar --include-non-distributable-layers
#imgpkg copy --tar /tmp/aspnet.tar --to-repo $TKG_CUSTOM_IMAGE_REPOSITORY/aspnet --registry-ca-cert-path ~/workspace/harbor-cacrt.crt --include-non-distributable-layers
```

### 1.2 Image Builder pre-requisites

1. You must obtain a Windows Server 2019 iso image, with the latest patch version August 2021 or later. You need to upload the iso file to your datastore’s [ISO] folder, noting the uploaded path.
2. Download the latest VMware Tools iso image (e.g: https://packages.vmware.com/tools/releases/latest/windows/VMware-tools-windows-12.1.5-20735119.iso) and upload to your datastore’s [ISO] folder, noting the uploaded path.

### 1.3 Deploy Image Builder Resource Kit

Change context to your management cluster (edit command for the right context name) and apply the `/windows/image/builder-airgapped.yaml` file included in this repo.

Make sure to edit the yaml to change the Harbor registry domain of the image to the one you are using. This is where you re-located the images before deploying the management cluster.

```bash
kubectl config use-context mgmt-admin@mgmt
kubectl apply -f ~/workspace/tkg-zone/windows/image/builder-airgapped.yaml
# check pods are Running
kubectl get pods -n imagebuilder
```

### 1.4 Prepare web server with CSI Proxy Binary

You need to build the CSI Proxy Binary as described in the upstream [CSI Proxy Build guide](https://github.com/kubernetes-csi/csi-proxy/tree/v1.1.1#build). In this guide we have used `v1.1.1` of the CSI Proxy and later versions should work.
Additional insights and details on building the `csi-proxy.exe` binary can also be found [here](/smb-csi/BuildCSIProxy.md) in this repo.

Once you have built the `csi-proxy.exe` binary you must upload it to the jumpbox from where you are operating in this guide. Then we will setup a web server to make this binary available during the Image Builder process.

```bash
# change directory to a suitable spot in your jumpbox (~/workspace/ in this guide)
mkdir -p ~/workspace/winres
# copy the csi-proxy.exe binary to that location
# no need to download the SSH Binary for TKG 2.3.0 since it's incldued in the windows bundle -curl -JOL https://github.com/PowerShell/Win32-OpenSSH/releases/download/v8.9.1.0p1-Beta/OpenSSH-Win64.zip
# download the Goss Binary
curl -JOL https://github.com/goss-org/goss/releases/download/v0.3.21/goss-alpha-windows-amd64.exe
cd ~/workspace/
set -m; nohup python3 -m http.server --directory winres > /dev/null 2>&1 & 
# Test your Jumpbox IP on port 8000 in your browser to confirm files are available and ready to be served. Example:
# http://10.220.72.54:8000
```

### 1.5 Create Configuration for Windows Image

Edit the `~/workspace/tkg-zone/windows/image/windows-airgapped.json` file and change the following fields:
- unattend_timezone: < your vcenter environment timezone> # hint: use `tzutil /l` on Windows to get a list of the supported timezone values, or check https://www.windowsafg.com/win10x86_x64_uefi.html
- password: < your vCenter password >
- username: < your vCenter username >
- datastore: < your vCenter datastore >
- datacenter: < your vCenter datacenter >
- cluster: < your vCenter cluster >
- folder: < your vCenter folder where to put the resulting template >
- debug_tools: < make sure this is set to false otherwise it will fail downloading these tools in an offline environment >
- vmtools_iso_path < your datastore iso path and vmware-tools iso name you uploaded earlier in this guide >
- network: < a vCenter portgroup/network available with DHCP enabled >
- os_iso_path: < your datastore iso path and windows-image iso name you uploaded earlier in this guide >
- vcenter_server: < your vCenter IP or FQDN >
- kubernetes_base_url, containerd_url, additional_executables_list, cloudbase_init_url, nssm_url, additional_executables_list, ssh_source_url: < change IP to the IP of one of the Control Plane nodes in your management cluster >
- wins_url: leave the empty string to prevent download and signal the process to continue without it
- goss_url: < change IP to the IP of the jumpbox where you launched your webserver >
- containerd_sha256_windows: < change sha256 to the value listed in your http://CONTROLPLANE-IP:30008/ response >
- windows_updates_categories: < make sure this is empty since windows updates need to be ignored in this airgapped image-builder steps >
- pause_image: < your internal registry pause image, which you relocated earlier >
- additional_prepull_images: < your internal registry servercore image, which you relocated earlier >
- additional_executables_list: notice we no longer use kube-proxy since we leverage antrea-proxy, part of the Antrea bundle; if you want to incldue the csi-proxy.exe in the Image and you prepared it in the step before, place here that internal URL of the web server you launched in the previous step (comma separated). E.g, add `,http://10.220.52.10:8000/csi-proxy.exe`

> Note: With the above configuration we are disabling Windows Updates. That's not realistic for a Production environment. There are ways to extend the image build process with an Ansible Role that can use previously downloaded Windows update offline files (MSU files) and install them in the Windows machine that is created during the image building process. This is not covered in this guide.

Check the `/windows/image/autounattend.xml` file in this repo:
- You may need to review the `ProductKey` and drive allocations match your requirements in your environment, especially if this template is built for a production environment that requires specific MAK keys. Remember the password in this file is temporary and will be removed prior to pushing the image into vSphere.

### 1.6 Create Windows Image

Run this command from the `/windows/image/` folder that contains the `windows-airgapped.json` and `autounattend.xml` you worked on the previous step. Adjust the `image-builder` container image URI to match with your Harbor registry.

```bash
# Get to the right folder first
cd ~/workspace/tkg-zone/windows/image/

docker run -it --rm --mount type=bind,source=$(pwd)/windows-airgapped.json,target=/windows.json --mount type=bind,source=$(pwd)/autounattend.xml,target=/home/imagebuilder/packer/ova/windows/windows-2019/autounattend.xml -e PACKER_VAR_FILES="/windows.json" -e IB_OVFTOOL=1 -e IB_OVFTOOL_ARGS='--skipManifestCheck' -e PACKER_FLAGS='-force -on-error=ask' -t harbor.h2o-4-14873.h2o.vmware.com/tkg/image-builder:v0.1.14_vmware.1 build-node-ova-vsphere-windows-2019
```

This process will take 60+ minutes: as it creates A VM in your vSphere environment, reboots it a few times and finally creates a vSphere VM Template out of it.


## 2. Create a TKG MultiOS cluster with Windows nodes

### 2.1 Prepare Cluster customizations

There are a few  customizations that are required for Windows/MultiOS clusters that on TKG 2.x.x require us to create a Custom ClusterClass and use jsonPatches in it.
- If you are deploying Windows Clusters in an air-gapped environment and/or using a Harbor registry wih self-signed certs you will also need to inject the CA Cert
- Disabling MHC for Windows nodes (it's prudent to do so because of Windows network stability but not mandatory)

TODOs: In prior versions we had customizations to enable shorter node names for windows nodes and autoscaler for windows node pools. Older implementations for this are not required but new implementations are a WIP due to some issues. Will be added asap.

Create Custom ClusterClass for MultiOS cluster and prepare Cluster Overlay
```bash
# Go to the folder in this repo that has all the cluster and ClusterClass configurations
cd ~/workspace/tkg-zone/windows/cluster/
# Get OOTB Clusterclass trimming to just the Clusterclass resource
cp ~/.config/tanzu/tkg/clusterclassconfigs/tkg-vsphere-default-v1.1.0.yaml tkg-vsphere-default-v1.1.0-thick.yaml
ytt -f tkg-vsphere-default-v1.1.0-thick.yaml -f filter.yaml > tkg-vsphere-default-v1.1.0.yaml
# Make a copy to customize for MultiOS tweaks
cp tkg-vsphere-default-v1.1.0.yaml tkg-vsphere-default-multios-ag-cc.yaml
# Change name
yq e -i '.metadata.name = "tkg-vsphere-default-multios-ag"' tkg-vsphere-default-multios-ag-cc.yaml # !!!! yq is adding extra spaces in some indentations making the file bigger. If you don't want this, just edit the original file and change the metadata.name manually

# If you are added the `csi-proxy.exe` binary in the `additional_executables_list` of your Windows json file, then add the following code in the `windows-antrea` json-patch in after row 2356 (after the Start Services block) in the custom cluster class yaml. include 18 spaces at the beginning of each row for the right indentation
vi tkg-vsphere-default-multios-ag-cc.yaml
            
            # Configure and Start CSI Proxy
            $csiflags = "-windows-service -log_file=C:\programdata\temp\csi-proxy.log -logtostderr=false"
            sc.exe create csiproxy binPath= "C:\programdata\temp\csi-proxy.exe $csiflags" start= auto
            sc.exe failure csiproxy reset= 0 actions= restart/10000
            sc.exe start csiproxy
# Use the repo's /windows/cluster/cc-win-cacert-overlay.yaml overlay to customize our ClusterClass definition with the Registry certificate
# Use the repo's /windows/cluster/cc-win-remove-mhc-overlay.yaml overlay to disable MHC for windows worker nodes if you need to
# and apply the ClusterClass in the MC:
ytt -f tkg-vsphere-default-multios-ag-cc.yaml -f cc-win-cacert-overlay.yaml | kubectl apply -f -
# Confirm new Clusterclass shows up when running:
kubectl get cc
# Output should look like this:
# NAME                             AGE
# tkg-vsphere-default-multios-ag   51s
# tkg-vsphere-default-v1.1.0       18h
# Edit the ./windows/cluster-overlay.yaml file and replace the Certificate with the one from your Harbor registry, which is located in `~/workspace/harbor-cacrt.crt`
vi cluster-overlay.yaml
```

### 2.2 Prepare OSImage and TKR configuration for Windows

Apply the repo's `/windows/cluster/win-osimage.yaml` file in this repository containing the OSImage resource for Windows. Adjust the Windows template accordingly to where it was placed in your envionment when you created the Windows Image:
```bash
cd ~/workspace/tkg-zone/windows/cluster/
kubectl apply -f win-osimage.yaml
```

Edit the v1.26.5 TKR to add windows `bootstrapPackage` and `osImage`:
```bash
kubectl edit tkr v1.26.5---vmware.2-tkg.1
# Add, keeping existing bootstrapPackages
# spec:
#    bootstrapPackages:
#    - name: tkg-windows.tanzu.vmware.com.0.30.0+vmware.1
# Add, keeping existing osImages
# spec:
#    osImages:
#    - name: v1.26.5---vmware.2-tkg.1-windows
```

### 2.3 Prepare MultiOS Cluster config files

Copy the `cluster-config.yaml` you used to deploy the management-cluster into a new `~/workspace/tkg-zone/windows/cluster/multios-cluster-config.yaml` file, then make some edits in it:
- Delete `AVI` keys, except `AVI_CONTROL_PLANE_HA_PROVIDER`
- Delete `ENABLE_CEIP_PARTICIPATION`
- Delete `MHC` keys
- Delete `LDAP` keys
- Delete `OIDC` keys
- Delete `DEPLOY_TKG_ON_VSPHERE7` and `ENABLE_TKGS_ON_VSPHERE7` (if present)
- Update the following properties to these default values (at least)
```bash
VSPHERE_WORKER_DISK_GIB: "80"
VSPHERE_WORKER_MEM_MIB: "16384"
VSPHERE_WORKER_NUM_CPUS: "4"
```
- Update `CLUSTER_NAME` with a suitable name for your Windows Cluster. In this guide we use `multios`
- Update `VSPHERE_CONTROL_PLANE_ENDPOINT` to one of the NSX-ALB (AVI) VIPs avaiable in the pool or leave empty for it to be auto-asigned
- Add the following properties
```bash
IS_WINDOWS_WORKLOAD_CLUSTER: "true"
WORKER_MACHINE_COUNT: 2
```
- Optionally add/edit these properties as desired:
```bash
# Enable Audit logs
ENABLE_AUDIT_LOGGING: "true"
```

Now create the classy config file
```bash
# go to the folder with all the windows cluster configurations
cd ~/workspace/tkg-zone/windows/cluster/

# Create classy config file
tanzu cluster create multios --file multios-cluster-config.yaml --dry-run > multios-classy-cluster-config.yaml

# Apply overlay to add Linux machineDeployment and variable to inject Harbor CA cert (if you added it earlier to the overlay). The result is a classy config file to create a MultiOS cluster that can pull images for our insecure Harbor registry.
ytt -f multios-classy-cluster-config.yaml -f cluster-overlay.yaml > multios-classy-cluster-config-customized.yaml
# TODO: Use the trust variable that has a additionalTrustedCAs with exactly the same CA in base64 format, and drop our additional variable.
```

### 2.4 Deploy Windows Cluster

Follow these steps:
```bash
# Deploy
tanzu cluster create -f multios-classy-cluster-config-customized.yaml -v 6
# take a stroll, it takes about 15 minutes, with windows nodes being fully Ready ~8min after they are created
```

Validate admin access to multios cluster
```bash
tanzu cluster kubeconfig get multios --admin
kubectl config use-context multios-admin@multios
kubectl get po -A
kubectl get no -owide
```

#### 2.5 Check Windows Processes are running

```bash
# SSH into a Windows node with the ssh key you created
ssh -i ./tkg-ssh-pub capv@192.168.14.33
#
# Check antrea agent is running
PS C:\Users\capv> Get-Process *antrea*
# Output should look like this:
# Handles  NPM(K)    PM(K)      WS(K)     CPU(s)     Id  SI ProcessName
# -------  ------    -----      -----     ------     --  -- -----------
#      99      10    27512      28660       0.44   2608   0 antrea-agent
#
# Check ovs is running:
PS C:\Users\capv> Get-Process *ovs*
# Output should look like this:
# Handles  NPM(K)    PM(K)      WS(K)     CPU(s)     Id  SI ProcessName
# -------  ------    -----      -----     ------     --  -- -----------
#       0       7     1628       6228              2636   0 ovsdb-server
#
# If you added the `csi-proxy.exe` binary and started it as a Windows Service, check it is running as a Windows Service
PS C:\Users\capv> Get-Process *csi-proxy*
# Output should look like this:
# Handles  NPM(K)    PM(K)      WS(K)     CPU(s)     Id  SI ProcessName
# -------  ------    -----      -----     ------     --  -- -----------
#     145      11    17080      11012       0.83   1832   0 csi-proxy
#
# Confirm location of the csi-proxy exe file and log
PS C:\Users\capv> cd c:\programdata\temp
PS C:\programdata\temp> dir
# Output should look like this:
#     Directory: C:\programdata\temp
#  
# Mode                LastWriteTime         Length Name
# ----                -------------         ------ ----
# -a----        9/19/2023  10:19 PM      142789925 antrea-windows-advanced.zip
# -a----        9/19/2023  10:20 PM       15011328 csi-proxy.exe
# -a----        9/20/2023   3:38 PM           1180 csi-proxy.log
```

## 3. Deploy SMB CSI Driver

Follow the [SMB CSI Driver setup guide](/smb-csi/README.md)

## 4. Deploy Prometheus Windows Exporter

Follow the [Prometheus Windows Exporter setup guide](/windows/metrics/README.md)

## 5. Deploy FluentBit

Follow the [Fluent-Bit Logging setup guide](/windows/logging/README.md)