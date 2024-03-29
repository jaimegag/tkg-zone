# SMB CSI Driver setup

This guide walks you through the steps to deploy and test the SMB CSI Driver, on both Linux and Windows nodes.

It expects the `csi-proxy.exe` binary to be included in the Windows nodes running as a Windows Service. The [Windows](/windows/README.md) guide in this repo include these steps to get that binary in the Windows image.
Additional insights and details on building the `csi-proxy.exe` binary can also be found [here](/smb-csi/BuildCSIProxy.md) in this repo.

The guide assumes an air-gapped environment and so images are relocated and yaml adjusted accordingly. If  your environment is not air-gapped ignore those steps.

## 1. Clone SMB CSI Upstream Repo

We have tested `v1.10.0` but yoyu can explore more recent versions.

```bash
git clone https://github.com/kubernetes-csi/csi-driver-smb.git
cd csi-driver-smb
git checkout v1.10.0
```

## 2. Relocate Container Images

Create `csi` project in your Harbor Registry, and make it public.

Relocate images: adjust the below commands accordingly to your Harbor Registry FQDN, location of Harbor Cert file and location of the docker authfile in your jumpbox.
```bash
mkdir -p ~/workspace/csi/

export REPO_LOCAL_FOLDER="/home/jaime/workspace/csi/"
export REPO_AUTH_FILE="/home/jaime/.docker/config.json"
export REPO_CERT_FOLDER="/home/jaime/workspace/"
export REPO_HARBOR_REGISTRY="harbor.h2o-4-14873.h2o.vmware.com"

# Linux
# csi-provisioner:v3.3.0
skopeo copy --override-os linux docker://registry.k8s.io/sig-storage/csi-provisioner:v3.3.0 docker-archive:${REPO_LOCAL_FOLDER}csi-provisioner-lin.tar
skopeo copy docker-archive:${REPO_LOCAL_FOLDER}csi-provisioner-lin.tar --dest-cert-dir=${REPO_CERT_FOLDER} --dest-authfile=${REPO_AUTH_FILE} docker://${REPO_HARBOR_REGISTRY}/csi/csi-provisioner:v3.3.0
# livenessprobe:v2.8.0
skopeo copy --override-os linux docker://registry.k8s.io/sig-storage/livenessprobe:v2.8.0 docker-archive:${REPO_LOCAL_FOLDER}livenessprobe-lin.tar
skopeo copy docker-archive:${REPO_LOCAL_FOLDER}livenessprobe-lin.tar --dest-cert-dir=${REPO_CERT_FOLDER} --dest-authfile=${REPO_AUTH_FILE} docker://${REPO_HARBOR_REGISTRY}/csi/livenessprobe:v2.8.0
# csi-node-driver-registrar:v2.6.2
skopeo copy --override-os linux docker://registry.k8s.io/sig-storage/csi-node-driver-registrar:v2.6.2 docker-archive:${REPO_LOCAL_FOLDER}csi-node-driver-registrar-lin.tar
skopeo copy docker-archive:${REPO_LOCAL_FOLDER}csi-node-driver-registrar-lin.tar --dest-cert-dir=${REPO_CERT_FOLDER} --dest-authfile=${REPO_AUTH_FILE} docker://${REPO_HARBOR_REGISTRY}/csi/csi-node-driver-registrar:v2.6.2
# smbplugin:v1.10.0
skopeo copy --override-os linux docker://registry.k8s.io/sig-storage/smbplugin:v1.10.0 docker-archive:${REPO_LOCAL_FOLDER}smbplugin-lin.tar
skopeo copy docker-archive:${REPO_LOCAL_FOLDER}smbplugin-lin.tar --dest-cert-dir=${REPO_CERT_FOLDER} --dest-authfile=${REPO_AUTH_FILE} docker://${REPO_HARBOR_REGISTRY}/csi/smbplugin:v1.10.0

# Windows
# livenessprobe:v2.8.0
skopeo copy --override-os windows docker://registry.k8s.io/sig-storage/livenessprobe:v2.8.0 docker-archive:${REPO_LOCAL_FOLDER}livenessprobe-win.tar
skopeo copy docker-archive:${REPO_LOCAL_FOLDER}livenessprobe-win.tar --dest-cert-dir=${REPO_CERT_FOLDER} --dest-authfile=${REPO_AUTH_FILE} docker://${REPO_HARBOR_REGISTRY}/csi/livenessprobe:v2.8.0-win
# csi-node-driver-registrar:v2.6.2
skopeo copy --override-os windows docker://registry.k8s.io/sig-storage/csi-node-driver-registrar:v2.6.2 docker-archive:${REPO_LOCAL_FOLDER}csi-node-driver-registrar-win.tar
skopeo copy docker-archive:${REPO_LOCAL_FOLDER}csi-node-driver-registrar-win.tar --dest-cert-dir=${REPO_CERT_FOLDER} --dest-authfile=${REPO_AUTH_FILE} docker://${REPO_HARBOR_REGISTRY}/csi/csi-node-driver-registrar:v2.6.2-win
# smbplugin:v1.10.0
skopeo copy --override-os windows docker://registry.k8s.io/sig-storage/smbplugin:v1.10.0 docker-archive:${REPO_LOCAL_FOLDER}smbplugin-win.tar
skopeo copy docker-archive:${REPO_LOCAL_FOLDER}smbplugin-win.tar --dest-cert-dir=${REPO_CERT_FOLDER} --dest-authfile=${REPO_AUTH_FILE} docker://${REPO_HARBOR_REGISTRY}/csi/smbplugin:v1.10.0-win
```

## 3. Deploy SMB CSI Driver

This lab will use the `yq` command. Pleae install it following instructions [here](https://github.com/mikefarah/yq#install) if not available yet in your jumpbox.

Since TKG 2.1 we will deploy eerything that follows in a Multi OS clsuter that you may have created in the [other labs](/windows/README.md) of this repository

### 3.1 Deploy RBAC, Driver config and Controller

Move to the folder where you cloned the upstream SMB CSI repo. Run this commands in all (Linux or Windows) clusters where you want to deploy the driver.

```bash
cd ~/workspace/csi-driver-smb/

# RBAC
kubectl apply -f ./deploy/rbac-csi-smb.yaml

# SMB CSI Driver
kubectl apply -f ./deploy/csi-smb-driver.yaml

# SMB CSI Controller
# Replace all image values with the velues that point to your internal Harbor registry where you relocated the images:
export CSI_PROVISIONER_IMAGE=$REPO_HARBOR_REGISTRY/csi/csi-provisioner:v3.3.0
export CSI_LIVENESS_PROBE_IMAGE=$REPO_HARBOR_REGISTRY/csi/livenessprobe:v2.8.0
export CSI_SMB_PLUGIN_IMAGE=$REPO_HARBOR_REGISTRY/csi/smbplugin:v1.10.0
yq e -i '.spec.template.spec.containers[0].image = strenv(CSI_PROVISIONER_IMAGE)' ./deploy/csi-smb-controller.yaml
yq e -i '.spec.template.spec.containers[1].image = strenv(CSI_LIVENESS_PROBE_IMAGE)' ./deploy/csi-smb-controller.yaml
yq e -i '.spec.template.spec.containers[2].image = strenv(CSI_SMB_PLUGIN_IMAGE)' ./deploy/csi-smb-controller.yaml
kubectl apply -f ./deploy/csi-smb-controller.yaml
```

### 3.2 Deploy Linux Nodes Plugin

```bash
# Replace all image values with the velues that point to your internal Harbor registry where you relocated the images:
export CSI_NODE_DRIVER_REGISTRAR_IMAGE=$REPO_HARBOR_REGISTRY/csi/csi-node-driver-registrar:v2.6.2
yq e -i 'select(.kind == "DaemonSet").spec.template.spec.containers[0].image = strenv(CSI_LIVENESS_PROBE_IMAGE)' ./deploy/csi-smb-node.yaml
yq e -i 'select(.kind == "DaemonSet").spec.template.spec.containers[1].image = strenv(CSI_NODE_DRIVER_REGISTRAR_IMAGE)' ./deploy/csi-smb-node.yaml
yq e -i 'select(.kind == "DaemonSet").spec.template.spec.containers[2].image = strenv(CSI_SMB_PLUGIN_IMAGE)' ./deploy/csi-smb-node.yaml
kubectl apply -f ./deploy/csi-smb-node.yaml
```

### 3.2 Deploy Windows Nodes Plugin

```bash
# Replace all image values with the velues that point to your internal Harbor registry where you relocated the images:
export CSI_LIVENESS_PROBE_WIN_IMAGE=$REPO_HARBOR_REGISTRY/csi/livenessprobe:v2.8.0-win
export CSI_NODE_DRIVER_REGISTRAR_WIN_IMAGE=$REPO_HARBOR_REGISTRY/csi/csi-node-driver-registrar:v2.6.2-win
export CSI_SMB_PLUGIN_WIN_IMAGE=$REPO_HARBOR_REGISTRY/csi/smbplugin:v1.10.0-win
yq e -i '.spec.template.spec.containers[0].image = strenv(CSI_LIVENESS_PROBE_WIN_IMAGE)' ./deploy/csi-smb-node-windows.yaml
yq e -i '.spec.template.spec.containers[1].image = strenv(CSI_NODE_DRIVER_REGISTRAR_WIN_IMAGE)' ./deploy/csi-smb-node-windows.yaml
yq e -i '.spec.template.spec.containers[2].image = strenv(CSI_SMB_PLUGIN_WIN_IMAGE)' ./deploy/csi-smb-node-windows.yaml

# Change the toleration.
#    - key: "os"
#      operator: "Equal"
#      value: "windows"
#      effect: "NoSchedule"
export CSI_WIN_TOLERATION_KEY="os"
export CSI_WIN_TOLERATION_OPERATOR="Equal"
export CSI_WIN_TOLERATION_VALUE="windows"
yq e -i '.spec.template.spec.tolerations[0].key = strenv(CSI_WIN_TOLERATION_KEY)' ./deploy/csi-smb-node-windows.yaml
yq e -i '.spec.template.spec.tolerations[0].operator = strenv(CSI_WIN_TOLERATION_OPERATOR)' ./deploy/csi-smb-node-windows.yaml
yq e -i '.spec.template.spec.tolerations[0].value = strenv(CSI_WIN_TOLERATION_VALUE)' ./deploy/csi-smb-node-windows.yaml
kubectl apply -f ./deploy/csi-smb-node-windows.yaml
```

## 4. Deploy SMB Server and tests

```bash
# Switch context to a separate linux cluster where to host the SMB server. Example (adjust to your context): 
kubectl config use-context lin-admin@lin

# Create secret
kubectl create secret generic smbcreds --from-literal username=smbadmin --from-literal password="gonative"
# Relocate images for SMB Server
skopeo copy --override-os linux docker://andyzhangx/samba:win-fix docker-archive:${REPO_LOCAL_FOLDER}samba-server.tar
skopeo copy docker-archive:${REPO_LOCAL_FOLDER}samba-server.tar --dest-cert-dir=${REPO_CERT_FOLDER} --dest-authfile=${REPO_AUTH_FILE} docker://${REPO_HARBOR_REGISTRY}/csi/samba-server:win-fix
# Update ./deploy/example/smb-provisioner/smb-server-lb.yaml with the right image
export CSI_SMB_SERVER_IMAGE=$REPO_HARBOR_REGISTRY/csi/samba-server:win-fix
yq e -i 'select(.kind == "Deployment").spec.template.spec.containers[0].image = strenv(CSI_SMB_SERVER_IMAGE)' ./deploy/example/smb-provisioner/smb-server-lb.yaml
# Deploy SMB Server
kubectl apply -f ./deploy/example/smb-provisioner/smb-server-lb.yaml
# Get the VIP from the server to use it in the test of the next section
kubectl get svc smb-server
```

### 4.1 Test from Linux node

We will use a storage class and deployment yaml from this repo. Change directory to the root of this repo. Then run the following commands:

```bash
# Change dir to this repo
cd  ~/workspace/tkg-zone/

# Switch back to our Multi OS cluster. Example (adjust to your context): 
kubectl config use-context multios-admin@multios
# We will leverage the linux nodes of the MultiOS cluster for the test app

# Create secret
kubectl create secret generic smbcreds --from-literal username=smbadmin --from-literal password="gonative"

# Deploy storage class
# Edit the ./smb-csi/smb-csi-storage-class.yaml file from this repo (not the csi-driver-smb one)
vi ./smb-csi/smb-csi-storage-class.yaml
#    Change parameters.source to use the IP of the SMB Server you created in the previous step
kubectl apply -f ./smb-csi/smb-csi-storage-class.yaml

# Deploy sample app with PVC to write on SMB storage from Linux node
# Relocate image for nginx 
skopeo copy --override-os linux docker://mcr.microsoft.com/oss/nginx/nginx:1.19.5 docker-archive:${REPO_LOCAL_FOLDER}nginx-lin.tar
skopeo copy docker-archive:${REPO_LOCAL_FOLDER}nginx-lin.tar --dest-cert-dir=${REPO_CERT_FOLDER} --dest-authfile=${REPO_AUTH_FILE} docker://${REPO_HARBOR_REGISTRY}/csi/nginx:1.19.5
# Update ./smb-csi/deployment-test-lin.yaml with the right image (we will also change PVC name to avoid conflict with the windows one)
export CSI_NGINX_IMAGE=$REPO_HARBOR_REGISTRY/csi/nginx:1.19.5
yq e -i 'select(.kind == "PersistentVolumeClaim").metadata.name = "pvc-smb-lin"' ./smb-csi/deployment-test-lin.yaml
yq e -i 'select(.kind == "Deployment").spec.template.spec.containers[0].image = strenv(CSI_NGINX_IMAGE)' ./smb-csi/deployment-test-lin.yaml
yq e -i 'select(.kind == "Deployment").spec.template.spec.volumes[0].persistentVolumeClaim.claimName = "pvc-smb-lin"' ./smb-csi/deployment-test-lin.yaml
# Deploy Linux nginx
kubectl apply -f ./smb-csi/deployment-test-lin.yaml
# Check the name of the volumne of the PVC created (e.g: pvc-aa7da6a2-4d78-4262-a940-8781c8f9982a)
kubectl get pvc
# Check the pod is writing rows with a timestamp in the mounted folder (adjust pod name to yours):
kubectl exec -it deployment-smb-56798dcb4-6w6r9 -- cat /mnt/smb/outfile
```

Check that the SMB server has that file in the correspomding folder.
```bash
# Switch context to the separate linux cluster where we host the SMB server. Example (adjust to your context): 
kubectl config use-context lin-admin@lin
# Confirm there is a folder in the SMB server for the volume id we got earlier (adjust pod name to yours):
kubectl exec -it smb-server-57b5b4bcf7-79b2c -- ls -lart /smbshare/
# Read the contents of the /smbshare/<linux-pvc-name>/outfile file in that server
kubectl exec -it smb-server-57b5b4bcf7-79b2c -- cat /smbshare/pvc-bd384f88-8eaf-4289-9b17-106e388e613c/outfile
# Content should match with what we see in the mounted volumne of the linux nginx test pod
```

### 4.2 Test from Windows node

```bash
# Switch back to our Multi OS cluster. Example (adjust to your context): 
kubectl config use-context multios-admin@multios

# Already created the secret and storage class

# Deploy sample app with PVC to write on SMB storage from Windows node
# Relocate image for Win busybox 
skopeo copy --override-os windows docker://e2eteam/busybox:1.29 docker-archive:${REPO_LOCAL_FOLDER}busybox-win.tar
skopeo copy docker-archive:${REPO_LOCAL_FOLDER}busybox-win.tar --dest-cert-dir=${REPO_CERT_FOLDER} --dest-authfile=${REPO_AUTH_FILE} docker://${REPO_HARBOR_REGISTRY}/csi/busybox:v1.29-win
# Update ./smb-csi/deployment-test-win.yaml with the right image
export CSI_BUSYBOX_WIN_IMAGE=$REPO_HARBOR_REGISTRY/csi/busybox:v1.29-win
yq e -i 'select(.kind == "Deployment").spec.template.spec.containers[0].image = strenv(CSI_BUSYBOX_WIN_IMAGE)' ./smb-csi/deployment-test-win.yaml
# Deploy Win busybox
kubectl apply -f ./smb-csi/deployment-test-win.yaml
# Check the name of the volumne of the PVC created (e.g: pvc-aa7da6a2-4d78-4262-a940-8781c8f9982a)
kubectl get pvc
# Check the pod is writing rows with a timestamp in the mounted folder (adjust pod name to yours):
kubectl exec -it busybox-smb-76fb996db8-s8glw -- cat C:\\mnt\\smb\\data.txt
```

Check that the SMB server has that file in the correspomding folder. Check in your linux cluster:
```bash
# Switch context to the separate linux cluster where we host the SMB server. Example (adjust to your context): 
kubectl config use-context lin-admin@lin
# Confirm there is a folder in the SMB server for the volume id we got earlier
kubectl exec -it smb-server-57b5b4bcf7-79b2c -- ls -lart /smbshare/
# Read the contents of the /smbshare/<linux-pvc-name>/subPath/data.txt file in that server
kubectl exec -it smb-server-57b5b4bcf7-79b2c -- cat /smbshare/pvc-bd384f88-8eaf-4289-9b17-106e388e613c/subPath/data.txt
# Content should match with what we see in the mounted volumne of the windows busybox test pod
```
