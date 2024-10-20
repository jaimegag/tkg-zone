# TKG baseline airgap installation

This guide provides a step by step guidde to deploy Tanzu Kubernetes Grid (v2.5.2) in an airgap environment. Based on the [official documentation](https://docs.vmware.com/en/VMware-Tanzu-Kubernetes-Grid/2.5/tkg-deploy-mc/mgmt-index.html) it provides an opinionated and concise way to prepare an environent/jumpbox, relocate container images and deploy a management cluster.

## Setup Environment

These are some sample steps combining recommendations from the official documentation and other personal suggestions to configure a jumpbox/workstation from where to manage the configuration and deployment of Tanzu Kubernetes Grid.

This guide assumes you have downloaded all the TKG v2.5.2 necessary artifacts from the [Broadcom Support Portal](https://support.broadcom.com/group/ecx/productfiles?subFamily=VMware%20Tanzu%20Kubernetes%20Grid&displayGroup=VMware%20Tanzu%20Kubernetes%20Grid&release=2.5.2&os=&servicePk=520705&language=EN):
- Ubuntu OVAs (1.30.2, 1.29.6, 1.28.11)
- Harbor Photon 4 OVA
- TKG Carvel Tools
- kubectl v1.30.2

Follow these commands to setup docker and CLIs, keeping an eye on the comments for guidance:
```
# Prepare the shell
sudo apt install zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# https://github.com/romkatv/powerlevel10k?tab=readme-ov-file#oh-my-zsh
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k

# Set ZSH_THEME="powerlevel10k/powerlevel10k" in ~/.zshrc

# Configure the docker daemon: adjust the registry FQND
vi /etc/docker/daemon.json
# Enter this text block:
# {
#   "exec-opts": ["native.cgroupdriver=systemd"],
#   "insecure-registries" : ["harbor.hyrulelab.com"]
# }

sudo systemctl daemon-reload
sudo systemctl restart docker

vi /etc/sysctl.d/90-override.conf
# Add this row:
# ipv4.conf.all.rp_filter = 0

sudo sysctl net/netfilter/nf_conntrack_max=131072

# Configure Tanzu CLI
sudo apt update
sudo apt install -y ca-certificates curl gpg
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://packages-prod.broadcom.com/tools/keys/VMWARE-PACKAGING-GPG-RSA-KEY.pub | sudo gpg --dearmor -o /etc/apt/keyrings/tanzu-archive-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/tanzu-archive-keyring.gpg] https://storage.googleapis.com/tanzu-cli-os-packages/apt tanzu-cli-jessie main" | sudo tee /etc/apt/sources.list.d/tanzu.list
sudo apt update
sudo apt install tanzu-cli=1.3.0

# Cleanup old installation to avoid any unexpected issue
rm -rf ~/.config/tanzu
rm -fr ~/.local/share/tanzu-cli

# Configure Tanzu CLI plugins
tanzu plugin clean
tanzu plugin group get vmware-tkg/default:v2.5.2
tanzu plugin group search -n vmware-tkg/default --show-details
tanzu plugin install --group vmware-tkg/default:v2.5.2

# Configure kubectl 
cd ~/downloads
gunzip kubectl-linux-v1.30.2+vmware.1.gz
chmod ugo+x kubectl-linux-v1.30.2+vmware.1
sudo install kubectl-linux-v1.30.2+vmware.1 /usr/local/bin/kubectl

# Install Carvel tools
gunzip tkg-carvel-tools-linux-amd64.tar.gz
tar -xvf tkg-carvel-tools-linux-amd64.tar
gunzip cli/imgpkg-linux-amd64-v0.36.0+vmware.2.gz
chmod +x cli/imgpkg-linux-amd64-v0.36.0+vmware.2
sudo cp cli/imgpkg-linux-amd64-v0.36.0+vmware.2 /usr/local/bin/imgpkg
gunzip cli/kapp-linux-amd64-v0.55.0+vmware.2.gz
chmod +x cli/kapp-linux-amd64-v0.55.0+vmware.2
sudo cp cli/kapp-linux-amd64-v0.55.0+vmware.2 /usr/local/bin/kapp
gunzip cli/kbld-linux-amd64-v0.37.0+vmware.2.gz
chmod +x cli/kbld-linux-amd64-v0.37.0+vmware.2
sudo cp cli/kbld-linux-amd64-v0.37.0+vmware.2 /usr/local/bin/kbld
gunzip cli/ytt-linux-amd64-v0.45.0+vmware.2.gz
chmod +x cli/ytt-linux-amd64-v0.45.0+vmware.2
sudo cp cli/ytt-linux-amd64-v0.45.0+vmware.2 /usr/local/bin/ytt

# Set Helpful Alias
echo "alias k=kubectl" >> ~/.bashrc
source ~/.bashrc

# Install yq - https://github.com/mikefarah/yq
sudo wget https://github.com/mikefarah/yq/releases/download/v4.44.3/yq_linux_amd64 -O /usr/bin/yq
sudo chmod +x /usr/bin/yq

# Install jq - https://stedolan.github.io/jq/
sudo apt-get install jq

# Install govc tool - https://github.com/vmware/govmomi/blob/master/govc/README.md#binaries
curl -LO "https://github.com/vmware/govmomi/releases/latest/download/govc_$(uname -s)_$(uname -m).tar.gz"
tar -xvzf govc_$(uname -s)_$(uname -m).tar.gz
sudo mv govc /usr/local/bin
rm govc_Linux_x86_64.tar.gz README.md LICENSE.txt CHANGELOG.md
```

## Prepare Harbor Container Registry


## Relocate Container Images 


## Deploy Management Cluster


## Deploy Linux Workload Cluster


