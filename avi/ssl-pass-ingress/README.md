# Deploy nginix pod and expose via L7 Ingress with TSL passthrrough to the pod

This deployment assumes the following:
- kubectl context pointing to existing k8s cluster
- AKO deployed in the k8s cluster with L7 configuration
- Wildcard FQDN configured (or able to be configured) to target the L7 NSX-ALB VS VIP
- kapp installed in your workstation

Deploy everything:
```bash
kapp deploy -a nginx-pass -f avi/ssl-pass-ingress/
```

Ingress configuration uses the passthrough annotation as described [here](https://avinetworks.com/docs/ako/1.5/passthrough-ingress/)

Check that you have all components in Ready/Running state:
```bash
$> k get po,svc,ingress
NAME                                  READY   STATUS    RESTARTS   AGE
pod/nginx-avi-pass-86694847d4-6492z   1/1     Running   0          18s
pod/nginx-avi-pass-86694847d4-ktt5z   1/1     Running   0          18s

NAME                             TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
service/kubernetes               ClusterIP   100.64.0.1      <none>        443/TCP   4h32m
service/nginx-avi-pass-service   ClusterIP   100.66.51.192   <none>        80/TCP    18s

NAME                                               CLASS    HOSTS                                      ADDRESS         PORTS   AGE
ingress.networking.k8s.io/nginx-avi-pass-ingress   avi-lb   nginx-pass.avi.tkg-vsp-lab.hyrulelab.com   192.168.15.19   80      18s
```

Without a proper server app that terminates TLS wee won't get a good ressponse, but by checking the logs we can verify the traffic is arriving encrypted to the nginx pod:
```bash
$> k logs pod/nginx-avi-pass-86694847d4-6492z
/docker-entrypoint.sh: Configuration complete; ready for start up
192.168.14.193 - - [06/Mar/2022:04:01:00 +0000] "\x16\x03\x01\x02\x00\x01\x00\x01\xFC\x03\x03\x5Cu\x90\xF4hr\x9E>\xE4\xC2^\xEEG\xD5U\xDB\x94\x8E\xA5\xA8\x95p\xE6m|\xD9lg\x99\x92z7 \xF9fu\xE1\xF3\xCE\xD6L\xDD%\xE0\xA3\xA8]\xABi\xBD\xD5\xDA\xC1\xF5\x10\xE9.\xC1\xF1r\xD4a\xF1\x0C\x8A\x00 \xAA\xAA\x13\x01\x13\x02\x13\x03\xC0+\xC0/\xC0,\xC00\xCC\xA9\xCC\xA8\xC0\x13\xC0\x14\x00\x9C\x00\x9D\x00/\x005\x01\x00\x01\x93\x8A\x8A\x00\x00\x00\x00\x00-\x00+\x00\x00(nginx-pass.avi.tkg-vsp-lab.hyrulelab.com\x00\x17\x00\x00\xFF\x01\x00\x01\x00\x00" 400 157 "-" "-" "-"
192.168.14.193 - - [06/Mar/2022:04:01:00 +0000] "\x16\x03\x01\x02\x00\x01\x00\x01\xFC\x03\x03=\xAF\x8B7\xB7\xE4\xAF\xD4\xB5\xCE\xF2\xD2\xDFDV \x0C\x07\x04\xDD\xF3\x00\xB5\xED\xEBJ\xD5\xF9\xECE\xF6\xF9 \xA8\x9E\xF4\xDE\x1E\xD6\xAB\x84\x98\x9B{\xD7h`\x12\xFD\x1C\xE6|6\xD8\xBF\xCA\xCD<\xED`\xD3\x91\x96\xEDC\x00 \xCA\xCA\x13\x01\x13\x02\x13\x03\xC0+\xC0/\xC0,\xC00\xCC\xA9\xCC\xA8\xC0\x13\xC0\x14\x00\x9C\x00\x9D\x00/\x005\x01\x00\x01\x93\xFA\xFA\x00\x00\x00\x00\x00-\x00+\x00\x00(nginx-pass.avi.tkg-vsp-lab.hyrulelab.com\x00\x17\x00\x00\xFF\x01\x00\x01\x00\x00" 400 157 "-" "-" "-"
192.168.14.193 - - [06/Mar/2022:04:01:30 +0000] "\x16\x03\x01\x02\x00\x01\x00\x01\xFC\x03\x03\x19-#\x8F\xC8\x15\xADvi\xEAD\x8D\xEE\x11\xEB!\xBC\x99\x1F\x84\xEA\xE9\xA8\x85\x102\xEB\x88\xB7^\x9F\xE0 {\xD0L\xF4g\x97\xA7\xEES\xD14Q><\xDC\xB7\xB3\xAEde\x85\x94\xC6\xED\x99\x11\x86\xC9K\xD3_\xCF\x00 zz\x13\x01\x13\x02\x13\x03\xC0+\xC0/\xC0,\xC00\xCC\xA9\xCC\xA8\xC0\x13\xC0\x14\x00\x9C\x00\x9D\x00/\x005\x01\x00\x01\x93::\x00\x00\x00\x00\x00-\x00+\x00\x00(nginx-pass.avi.tkg-vsp-lab.hyrulelab.com\x00\x17\x00\x00\xFF\x01\x00\x01\x00\x00" 400 157 "-" "-" "-"
```

For reference on the NSX-ALB side, this creates two NSX-ALB Virtual Services:
- One Virtual Services that would listen on port 443, name would be of the format clustername–‘Shared-Passthrough’-shardnumber.
- For passthrough hosts in Ingress, another Virtual Service is created for each shared L4 VS, to handle insecure traffic on port 80.

![AVI Pass](/docs/avi-pass.png)