# Ingress Samples with NSX-ALB (AVI)

## 1. Deploy nginix pod and expose with regular Ingress configuration

Deploy app:
```bash
kubectl apply -f avi/ingress/nginx-ingress.yaml
```

## 2. [Deploy sample pod and expose via L7 Ingress with TLS termination on NSX-ALB (AVI) side](/avi/ssl-ingress/README.md)

## 3. [Deploy sample pod and expose via L7 Ingress with TLS passthrough to the pod](/avi/ssl-pass-ingress/README.md)