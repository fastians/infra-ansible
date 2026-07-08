# SALOME — Kubernetes / Karpenter Deployment

## Architecture

```
EFS Filesystem (one-time setup)
  └── salome-sif PVC   (ReadOnlyMany)  ← 5.6 GB SIF, shared by all pods
  └── salome-jobs PVC  (ReadWriteMany) ← job outputs
  └── salome-bundles PVC (ReadWriteMany) ← CAD bundles

Karpenter NodePool: salome
  └── r7i.8xlarge  (32 vCPU / 256 GiB / 1 TB gp3)
  └── taint: workload=salome:NoSchedule

Pod: salome-api
  ├── initContainer: sif-check  (fails fast if SIF incomplete)
  └── container: salome-api     (FastAPI + Apptainer, privileged)
```

The SIF is **never baked into the Docker image** and **never downloaded per pod**.
It lives on EFS, uploaded exactly once via `job-sif-upload.yaml`.

## Prerequisites

1. EKS cluster with Karpenter installed
2. EFS CSI driver installed (`aws-efs-csi-driver`)
3. An EFS filesystem created — put its ID in `storageclass-efs.yaml`
4. Karpenter `instanceProfile` created — update `karpenter-nodepool.yaml`
5. Subnets and security groups tagged with `karpenter.sh/discovery: mek-lab`
6. Docker image pushed to ECR — update `deployment.yaml`

## Deploy order

```bash
# 1. Namespace + Service (creates namespace first)
kubectl apply -f k8s/service.yaml

# 2. Storage
kubectl apply -f k8s/storageclass-efs.yaml
kubectl apply -f k8s/pvc-sif.yaml
kubectl apply -f k8s/pvc-jobs.yaml

# 3. Karpenter NodePool (so a node is available for the upload Job)
kubectl apply -f k8s/karpenter-nodepool.yaml

# 4. Upload SIF to EFS — one-time, ~5.6 GB download
kubectl apply -f k8s/job-sif-upload.yaml
kubectl -n salome logs -f job/sif-upload

# 5. Deploy the API
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/deployment.yaml
```

## Updating the app (no SIF re-download)

```bash
# Build + push new image
docker build -t YOUR_ECR/mek-lab/salome-api:v2 .
docker push YOUR_ECR/mek-lab/salome-api:v2

# Roll out
kubectl -n salome set image deployment/salome-api salome-api=YOUR_ECR/mek-lab/salome-api:v2
```

The EFS SIF PVC is untouched — pods on new Karpenter nodes mount the same EFS data instantly.
