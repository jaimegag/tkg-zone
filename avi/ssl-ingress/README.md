# Deploy nginix pod and expose via L7 Ingress with TLS termination on NSX-ALB (AVI) side

This deployment assumes the following:
- kubectl context pointing to existing k8s cluster
- cert-manager deployed in the k8s cluster
- AKO deployed in the k8s cluster with L7 configuration
- Wildcard FQDN configured (or able to be configured) to target the L7 NSX-ALB VS VIP
- kapp installed in your workstation
> Note: You can use your own custom k8s secret with ca/crt/key instead of leveraging cert-manager

Deploy everything:
```bash
kapp deploy -a nginx-ssl -f avi/ssl-ingress/
```

This will create a self-signed certificate using cert-manager and configue the Ingress services to use it.
> Note: Change the FQDNs in the yaml to match those from your environment

Check that you have all components in Ready/Running state:
```bash
$> k get secret,certificate,po,svc,ingress
NAME                         TYPE                                  DATA   AGE
secret/default-token-9msvq   kubernetes.io/service-account-token   3      156m
secret/nginx-cert-tls        kubernetes.io/tls                     3      138m

NAME                                     READY   SECRET           AGE
certificate.cert-manager.io/nginx-cert   True    nginx-cert-tls   138m

NAME                                         READY   STATUS    RESTARTS   AGE
pod/nginx-avi-ssl-ingress-74856b86bf-kgrld   1/1     Running   0          138m
pod/nginx-avi-ssl-ingress-74856b86bf-td6hs   1/1     Running   0          138m

NAME                            TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
service/kubernetes              ClusterIP   100.64.0.1      <none>        443/TCP   156m
service/nginx-avi-ssl-service   ClusterIP   100.71.220.46   <none>        80/TCP    138m

NAME                                              CLASS    HOSTS                                     ADDRESS         PORTS     AGE
ingress.networking.k8s.io/nginx-avi-ssl-ingress   <none>   nginx-ssl.avi.tkg-vsp-lab.hyrulelab.com   192.168.15.15   80, 443   138m
```

In your browser the URL should be `https` but considered `Not Secure`:
![NGINX Welcome](/docs/nginx-welcome.png)
You can always check the certtifiate is the one you configurerd:
![NGINX Crt](/docs/nginx-crt.png)
> Note: If you use a different Issuer (e.g: Let's Encrypt / Acme) or trusted cert, then your cert may be considered Secured by your browser.

For reference on the NSX-ALB side, this creates two NSX-ALB Virtual Services:
- One Shared-L7 Virtual Services that would listen on ports 80 and 443
- One child Virtual Service for the Shared-L7 with the dedicated pool including the destination pods.

![AVI Pass](/docs/avi-ssl.png)