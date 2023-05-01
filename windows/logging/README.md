# Fluent-Bit Logging setup

This guide walks you through the steps to deploy and test Fluent-Bit on Windows nodes, and connect it to a ElasticSearch+Kibana comonent running in the Linux cluster.

The Fluent-Bit configuration has been influenced from several sources [ [1](https://aws.amazon.com/blogs/containers/centralized-logging-for-windows-containers-on-amazon-eks-using-fluent-bit/) | [2](https://docs.vmware.com/en/VMware-Tanzu-Kubernetes-Grid-Integrated-Edition/1.15/tkgi/GUID-windows-logging.html#configure-fluent-bit-6) | [3](https://docs.fluentbit.io/manual/installation/kubernetes#windows-deployment) ], plus includes a few filters and Lua scripts to improve the log parsing. Credit to `Itay Talmi`.

The ElasticSearch and Kibana configuration has been reused from the TKG-Lab repository [here](https://github.com/Tanzu-Solutions-Engineering/tkg-lab/blob/main/docs/shared-services-cluster/06_ek_ssc.md). Simplified to use service of type LB instead of Ingress.

The guide assumes an air-gapped environment and so images are relocated and yaml adjusted accordingly. If  your environment is not air-gapped ignore those steps.

# 1. Relocate Container Images

For simplicity we will reuse the existing `tkg` project in the Harbor registry.

Relocate images: adjust the below commands accordingly to your Harbor Registry FQDN, location of Harbor Cert file and location of the docker authfile in your jumpbox.
```bash
mkdir -p ~/workspace/logging

export REPO_LOCAL_FOLDER="/home/jaime/workspace/csi/"
export REPO_AUTH_FILE="/home/jaime/.docker/config.json"
export REPO_CERT_FOLDER="/home/jaime/workspace/"
export REPO_HARBOR_REGISTRY="harbor.h2o-4-1056.h2o.vmware.com"

# elasticsearch
skopeo copy docker://docker.io/bitnami/elasticsearch:7.2.1 docker-archive:${REPO_LOCAL_FOLDER}elasticsearch.tar
skopeo copy docker-archive:${REPO_LOCAL_FOLDER}elasticsearch.tar --dest-cert-dir=${REPO_CERT_FOLDER} --dest-authfile=${REPO_AUTH_FILE} docker://${REPO_HARBOR_REGISTRY}/tkg/elasticsearch:7.2.1
skopeo copy docker://docker.io/bitnami/bitnami-shell:10-debian-10-r138 docker-archive:${REPO_LOCAL_FOLDER}bitnamishell.tar
skopeo copy docker-archive:${REPO_LOCAL_FOLDER}bitnamishell.tar --dest-cert-dir=${REPO_CERT_FOLDER} --dest-authfile=${REPO_AUTH_FILE} docker://${REPO_HARBOR_REGISTRY}/tkg/bitnami-shell:10-debian-10-r138

# kibana
skopeo copy docker://docker.io/bitnami/kibana:7.2.1 docker-archive:${REPO_LOCAL_FOLDER}/kibana.tar
skopeo copy docker-archive:${REPO_LOCAL_FOLDER}kibana.tar --dest-cert-dir=${REPO_CERT_FOLDER} --dest-authfile=${REPO_AUTH_FILE} docker://${REPO_HARBOR_REGISTRY}/tkg/kibana:7.2.1

# fluent-bit
skopeo --override-os windows copy docker://fluent/fluent-bit:windows-2019-2.0.6 docker-archive:${REPO_LOCAL_FOLDER}fb-win.tar
skopeo copy docker-archive:${REPO_LOCAL_FOLDER}fb-win.tar --dest-cert-dir=${REPO_CERT_FOLDER} --dest-authfile=${REPO_AUTH_FILE} docker://${REPO_HARBOR_REGISTRY}/tkg/fluent-bit:windows-2019-2.0.6

# logspewer (log generator for windows)
skopeo --override-os windows copy docker://pivotalgreenhouse/logspewer:latest docker-archive:${REPO_LOCAL_FOLDER}logspewer.tar
skopeo copy docker-archive:${REPO_LOCAL_FOLDER}logspewer.tar --dest-cert-dir=${REPO_CERT_FOLDER} --dest-authfile=${REPO_AUTH_FILE} docker://${REPO_HARBOR_REGISTRY}/tkg/logspewer:latest
```

# 2. Deploy ElasticSearch and Kibana

Run these commands to deploy Elasticsearch:
```bash
# Change directory to the logging folder of this repo
cd ~/workspace/tkg-zone/windows/logging/
# Switch context to separate Linux cluster. Example (adjust to your context):
kubectl config use-context lin-admin@lin
# Adjust yaml configuration to use the relocated images in your repo
export ELASTICSEARCH_IMAGE=$REPO_HARBOR_REGISTRY/tkg/elasticsearch:7.2.1
export BITNAMISHELL_IMAGE=$REPO_HARBOR_REGISTRY/tkg/bitnami-shell:10-debian-10-r138
yq e -i 'select(.kind == "StatefulSet").spec.template.spec.containers[0].image = strenv(ELASTICSEARCH_IMAGE)' ./elasticsearch.yaml
yq e -i 'select(.kind == "StatefulSet").spec.template.spec.initContainers[0].image = strenv(BITNAMISHELL_IMAGE)' ./elasticsearch.yaml
yq e -i 'select(.kind == "StatefulSet").spec.template.spec.initContainers[1].image = strenv(BITNAMISHELL_IMAGE)' ./elasticsearch.yaml
yq e -i 'select(.kind == "StatefulSet").spec.template.spec.initContainers[2].image = strenv(BITNAMISHELL_IMAGE)' ./elasticsearch.yaml
# From the root of this repo run
kubectl apply -f ./elasticsearch.yaml
# Get the ElasticSearch VIP to use it in the kibana service
kubectl get svc elasticsearch -n elasticsearch-kibana
```

Edit `/windows/logging/kibana.yaml` to change the `ELASTICSEARCH_URL` with the IP or VIP of the ElasticSearch Service. Then run these commands
```bash
# Change directory to the logging folder of this repo
cd ~/workspace/tkg-zone/windows/logging/
# Switch context to separate Linux cluster. Example (adjust to your context):
kubectl config use-context lin-admin@lin
# Adjust yaml configuration to use the relocated images in your repo
export KIBANA_IMAGE=$REPO_HARBOR_REGISTRY/tkg/kibana:7.2.1
yq e -i 'select(.kind == "Deployment").spec.template.spec.containers[0].image = strenv(KIBANA_IMAGE)' ./kibana.yaml
# From the root of this repo run
kubectl apply -f ./kibana.yaml
```

Check ElasticSearch and Kibana are deployed and you have LB IPs.
```bash
kubectl get all -n elasticsearch-kibana
# Output should look like this:
# NAME                          READY   STATUS    RESTARTS   AGE
# pod/elasticsearch-0           1/1     Running   0          6m4s
# pod/kibana-6864b54c6f-x8ll8   1/1     Running   0          109s

# NAME                    TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)                         AGE
# service/elasticsearch   LoadBalancer   100.67.72.26    10.220.35.217   9200:32360/TCP,9300:30142/TCP   6m4s
# service/kibana          LoadBalancer   100.65.130.69   10.220.35.218   5601:31308/TCP                  109s

# NAME                     READY   UP-TO-DATE   AVAILABLE   AGE
# deployment.apps/kibana   1/1     1            1           109s

# NAME                                DESIRED   CURRENT   READY   AGE
# replicaset.apps/kibana-6864b54c6f   1         1         1       109s

# NAME                             READY   AGE
# statefulset.apps/elasticsearch   1/1     6m4s
```

# 3. Deploy Fluent-Bit

Edit `/windows/logging/fb-win.yaml` and change the ES host in the OUTPUT section of the ConfigMAp (line 64): Use the ElasticSearch IP you got in the previous section of this guide. Optionally adjust the FILTER in row 98 to your cluster needs. Then run these commands:
```bash
# Change directory to the logging folder of this repo
cd ~/workspace/tkg-zone/windows/logging/
# Switch context to MultiOS cluster. Example (adjust to your context):
kubectl config use-context multios-admin@multios
# Adjust yaml configuration to use the relocated images in your repo
export FLUENTBIT_IMAGE=$REPO_HARBOR_REGISTRY/tkg/fluent-bit:windows-2019-2.0.6
yq e -i 'select(.kind == "DaemonSet").spec.template.spec.containers[0].image = strenv(FLUENTBIT_IMAGE)' ./fb-win.yaml
# Deploy Fluent Bit DaemonSet
kubectl apply -f ./fb-win.yaml
# After a few minutes, confirm the pods are running
kubectl get all -n logging
# Output should look like this:
# NAME                           READY   STATUS    RESTARTS   AGE
# pod/fluent-bit-windows-8zrhr   1/1     Running   0          10m
# pod/fluent-bit-windows-cjgts   1/1     Running   0          10m
# pod/fluent-bit-windows-jx282   1/1     Running   0          10m

# NAME                                DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR              AGE
# daemonset.apps/fluent-bit-windows   3         3         3       3            3           kubernetes.io/os=windows   10m
```

# 4. Test and Access logs via Kibana

Deploy a Windows app to generate some log traces to be colected by FluentBit and sent to ElasticSearch. Run these commands:
```bash
# Change directory to the logging folder of this repo
cd ~/workspace/tkg-zone/windows/logging/
# Switch context to MultiOS cluster. Example (adjust to your context):
kubectl config use-context multios-admin@multios
# Adjust yaml configuration to use the relocated images in your repo
export LOGSPEWER_IMAGE=$REPO_HARBOR_REGISTRY/tkg/logspewer:latest
yq e -i 'select(.kind == "DaemonSet").spec.template.spec.containers[0].image = strenv(LOGSPEWER_IMAGE)' ./logspewer.yaml
kubectl apply -f ./logspewer.yaml
# Wait for pods to be up and running (this may take more than 5 min)
kubectl get po
# Output should look like this:
# NAME              READY   STATUS    RESTARTS   AGE
# logspewer-8nvtz   1/1     Running   0          6m23s
# logspewer-hfdgp   1/1     Running   0          6m23s
# logspewer-qdbp4   1/1     Running   0          6m23s

# Wait for a few logs to be written by the pods
kubectl logs pod/logspewer-lpkd4
# [2022-12-09T17:39:12Z] [LOGSPEWER] Initializing...
# [2022-12-09T17:39:22Z] [LOGSPEWER] ping from logspewer
# [2022-12-09T17:39:32Z] [LOGSPEWER] ping from logspewer
# [2022-12-09T17:39:42Z] [LOGSPEWER] ping from logspewer
# [2022-12-09T17:39:52Z] [LOGSPEWER] ping from logspewer
# [2022-12-09T17:40:02Z] [LOGSPEWER] ping from logspewer
# [2022-12-09T17:40:12Z] [LOGSPEWER] ping from logspewer
# [2022-12-09T17:40:22Z] [LOGSPEWER] ping from logspewer
# [2022-12-09T17:40:32Z] [LOGSPEWER] ping from logspewer
# [2022-12-09T17:40:42Z] [LOGSPEWER] ping from logspewer
# [2022-12-09T17:40:52Z] [LOGSPEWER] ping from logspewer
# ...
```

Access the Kibana Dashboard using the Kibana LB IP:Port you got earlier in this guide:
- Click on the Discover icon at the top of the left menu bar.
- You will see widget to create an index pattern. Enter `k8s-syslog*` and click next step.
- Select @timestamp for the Time filter field name. and then click Create index pattern.
- Now click the Discover icon at the top of the left menu bar. You can start searching for logs.

Here's a sample screenshot of what you should be seeing in the Kibana UI: logspewer log traces, and even the windows-exporter and fluent-bit pod log traces: ![kibana-win](/windows/logging/kibana-win.png)

