# Windows Containers sample apps

## Deploy ASP.NET app

Deploy app:
```bash
kubectl apply -f windows/samples/aspnet.yaml
```

Wait ~5-10 min if it's the first time you deploy it in a given k8s cluster, since the container images are big.

Check everything is up and running
```bash
$> kubectl get all

NAME                          READY   STATUS    RESTARTS   AGE
pod/aspnet-7b78876886-s2525   1/1     Running   0          92s

NAME                 TYPE           CLUSTER-IP       EXTERNAL-IP     PORT(S)        AGE
service/aspnet       LoadBalancer   100.65.126.218   192.168.15.15   80:30852/TCP   92s
service/kubernetes   ClusterIP      100.64.0.1       <none>          443/TCP        2d14h

NAME                     READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/aspnet   1/1     1            1           92s

NAME                                DESIRED   CURRENT   READY   AGE
replicaset.apps/aspnet-7b78876886   1         1         1       92s
```

Get the `EXTERNAL-IP` of the aspnet service and access the app in the browser once the aspnet pod is `Running`.

You should see a page like this:

![ASP.NET App](/img/aspnet-landing.png)


## Deploy IIS app

Deploy app:
```bash
kubectl apply -f windows/samples/iis.yaml
```

Wait ~5-10 min if it's the first time you deploy it in a given k8s cluster, since the container images are big.

Check everything is up and running
```bash
$> kubectl get all

NAME                       READY   STATUS    RESTARTS   AGE
pod/iis-84646bccdc-tgbvh   1/1     Running   0          5m27s

NAME                 TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)        AGE
service/iis          LoadBalancer   100.69.69.191   192.168.15.15   80:31731/TCP   5m27s
service/kubernetes   ClusterIP      100.64.0.1      <none>          443/TCP        2d14h

NAME                  READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/iis   1/1     1            1           5m27s

NAME                             DESIRED   CURRENT   READY   AGE
replicaset.apps/iis-84646bccdc   1         1         1       5m27s
```

Get the `EXTERNAL-IP` of the iis service and access the app in the browser once the iis pod is `Running`

You should see a page like this:

![ASP.NET App](/img/iis-landing.png)

## Deploy Console app

Deploy app:
```bash
kubectl apply -f windows/samples/dotnet.yaml
```

Wait ~5-10 min if it's the first time you deploy it in a given k8s cluster, since the container images are big.

Check everything is up and running
```bash
$> kubectl get all

NAME                          READY   STATUS    RESTARTS   AGE
pod/dotnet-6b685c487f-9vmff   1/1     Running   0          8s

NAME                 TYPE           CLUSTER-IP       EXTERNAL-IP     PORT(S)        AGE
service/dotnet       LoadBalancer   100.65.130.244   192.168.15.15   80:31346/TCP   8s
service/kubernetes   ClusterIP      100.64.0.1       <none>          443/TCP        2d14h

NAME                     READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/dotnet   1/1     1            1           8s

NAME                                DESIRED   CURRENT   READY   AGE
replicaset.apps/dotnet-6b685c487f   1         1         1       8s
```

This app will run and end so it will move from `Running` to `CrashLoopBackOff` quickly.
To confirm it has run properly check the logs of the pod, you should see an output like the one below the command:
```bash
$> kubectl logs pod/dotnet-6b685c487f-9vmff                
                                 ad88
                        ,d      d8"
                        88      88
8b,dPPYba,   ,adPPYba, MM88MMM MM88MMM 8b,     ,d8
88P'   `"8a a8P_____88   88      88     `Y8, ,8P'
88       88 8PP"""""""   88      88       )888(
88       88 "8b,   ,aa   88,     88     ,d8" "8b,
88       88  `"Ybbd8"'   "Y888   88    8P'     `Y8

.NET Framework 4.8.4465.0
Microsoft Windows 10.0.17763 

OSArchitecture: X64
ProcessorCount: 2
```