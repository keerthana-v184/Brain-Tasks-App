# Brain Tasks React Application Deployment on AWS EKS using CI/CD

This project demonstrates the end-to-end deployment of a React application using a modern DevOps toolchain on AWS. It uses Docker, Amazon ECR, Kubernetes on EKS, AWS CodePipeline, CodeBuild, CodeDeploy, and CloudWatch for monitoring.

---

## Table of Contents

* [Project Overview](#project-overview)
* [Workflow Overview](#workflow-overview)
* [1. Prerequisites](#1-prerequisites)
* [2. Repository Setup](#2-repository-setup)
* [3. Dockerization](#3-dockerization)

  * [Dockerfile](#dockerfile)
* [4. Amazon ECR](#4-amazon-ecr)
* [5. Kubernetes on AWS EKS](#5-kubernetes-on-aws-eks)

  * [deployment.yml](#deploymentyml)
  * [service.yml](#serviceyml)
  * [cloudwatch-configmap.yml](#cloudwatch-configmapyml)
* [6. CI/CD Pipeline with AWS](#6-cicd-pipeline-with-aws)

  * [buildspec.yml](#buildspecyml)
  * [appspec.yml](#appspecyml)
  * [deploy.sh](#deploysh)
* [7. Monitoring with CloudWatch](#7-monitoring-with-cloudwatch)
* [8. Access and Verification](#8-access-and-verification)
* [9. Learning Outcome](#9-learning-outcome)

---

## Project Overview

This project involves deploying a production-ready React application (`Brain Tasks App`) to AWS infrastructure using a complete CI/CD pipeline. The application is containerized with Docker, stored on AWS Elastic Container Registry (ECR), and deployed to Amazon EKS. CodeBuild automates the build and push, while CodeDeploy handles deployment to Kubernetes. CloudWatch is configured to collect and monitor application logs.

---

## Workflow Overview

1. Fork the React app from GitHub
2. Dockerize the app and build the image
3. Push image to Amazon ECR
4. Set up EKS cluster and deploy with YAML files
5. Set up AWS CodePipeline: GitHub → CodeBuild → CodeDeploy → EKS
6. Configure monitoring with CloudWatch Agent
7. Application available via LoadBalancer on port 3000

---

## 1. Prerequisites

* AWS account with permissions for ECR, EKS, IAM, CodePipeline, CodeBuild, CodeDeploy
* GitHub repo forked from original source
* Docker installed locally
* AWS CLI and `kubectl` configured

---

## 2. Repository Setup

```bash
git clone https://github.com/keerthana-v184/Brain-Tasks-App.git
cd Brain-Tasks-App
git checkout -b main
```

### File Structure

```
Brain-Tasks-App/
├── Dockerfile
├── appspec.yml
├── buildspec.yml
├── deployment.yml
├── service.yml
├── scripts/
│   └── deploy.sh
└── cloudwatch-configmap.yml
```

---

## 3. Dockerization

### Dockerfile

```Dockerfile
FROM nginx:alpine
COPY ./dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

---

## 4. Amazon ECR

Create an ECR repo named `brain-tasks-app`:

```bash
aws ecr create-repository \
  --repository-name brain-tasks-app \
  --region us-east-1
```

Login and tag image:

```bash
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin <your-aws-account-id>.dkr.ecr.us-east-1.amazonaws.com

docker build -t brain-tasks-app .
docker tag brain-tasks-app:latest <your-aws-account-id>.dkr.ecr.us-east-1.amazonaws.com/brain-tasks-app:v1
docker push <your-aws-account-id>.dkr.ecr.us-east-1.amazonaws.com/brain-tasks-app:v1
```

---

## 5. Kubernetes on AWS EKS

### deployment.yml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: brain-tasks-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: brain-tasks
  template:
    metadata:
      labels:
        app: brain-tasks
    spec:
      containers:
      - name: brain-tasks-container
        image: <your-aws-account-id>.dkr.ecr.us-east-1.amazonaws.com/brain-tasks-app:v1
        ports:
        - containerPort: 80
        volumeMounts:
        - name: nginx-logs
          mountPath: /var/log/nginx

      - name: cloudwatch-agent
        image: amazon/cloudwatch-agent:latest
        volumeMounts:
        - name: nginx-logs
          mountPath: /var/log/nginx
        - name: cwagent-config
          mountPath: /etc/cwagentconfig
          readOnly: true
        args:
        - -config
        - /etc/cwagentconfig/cwagentconfig.json
        - -envconfig

      volumes:
      - name: nginx-logs
        emptyDir: {}
      - name: cwagent-config
        configMap:
          name: cwagentconfig
```

### service.yml

```yaml
apiVersion: v1
kind: Service
metadata:
  name: brain-tasks-service
spec:
  selector:
    app: brain-tasks
  type: LoadBalancer
  ports:
    - protocol: TCP
      port: 3000
      targetPort: 80
```

### cloudwatch-configmap.yml

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cwagentconfig
data:
  cwagentconfig.json: |
    {
      "logs": {
        "logs_collected": {
          "files": {
            "collect_list": [
              {
                "file_path": "/var/log/nginx/access.log",
                "log_group_name": "/brain-tasks/nginx-access",
                "log_stream_name": "{hostname}/access.log",
                "timestamp_format": "%d/%b/%Y:%H:%M:%S %z"
              },
              {
                "file_path": "/var/log/nginx/error.log",
                "log_group_name": "/brain-tasks/nginx-error",
                "log_stream_name": "{hostname}/error.log"
              }
            ]
          }
        }
      }
    }
```

---

## 6. CI/CD Pipeline with AWS

### buildspec.yml

```yaml
version: 0.2

phases:
  pre_build:
    commands:
      - echo Logging in to DockerHub...
      - echo $DOCKERHUB_PASSWORD | docker login -u $DOCKERHUB_USERNAME --password-stdin
      - echo Logging in to Amazon ECR...
      - aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <your-aws-account-id>.dkr.ecr.us-east-1.amazonaws.com
      - export REPOSITORY_URL=<your-aws-account-id>.dkr.ecr.us-east-1.amazonaws.com/brain-tasks-app
      - export IMAGE_TAG=v1
  build:
    commands:
      - docker build -t $REPOSITORY_URL:$IMAGE_TAG .
  post_build:
    commands:
      - docker push $REPOSITORY_URL:$IMAGE_TAG
      - aws eks update-kubeconfig --region us-east-1 --name brain-tasks-cluster
artifacts:
  files:
    - appspec.yml
    - deployment.yml
    - service.yml
```

### appspec.yml

```yaml
version: 0.0
Resources:
  - Kubernetes:
      Manifest:
        - deployment.yml
        - service.yml
      LoadBalancerInfo:
        ContainerName: brain-tasks-container
        ContainerPort: 80
RoleArn: arn:aws:iam::<your-aws-account-id>:role/Codedeploy-EKS-Role

hooks:
  AfterAllowTestTraffic:
    - location: scripts/deploy.sh
      timeout: 300
      runas: root
```

### deploy.sh

```bash
#!/bin/bash
kubectl apply -f cloudwatch-configmap.yml
kubectl apply -f deployment.yml
kubectl apply -f service.yml
```

---

## 7. Monitoring with CloudWatch

* CloudWatch agent is installed as a sidecar in the deployment.
* `cloudwatch-configmap.yml` defines the log collection config.
* Logs from NGINX access and error are pushed to CloudWatch log groups:

  * `/brain-tasks/nginx-access`
  * `/brain-tasks/nginx-error`

Enable EKS node IAM role with permission for CloudWatch agent to push logs.

---

## 8. Access and Verification

* **Deployed React App URL** (via Kubernetes LoadBalancer):

  ```
  http://a54b3d59d1de144b3aa168c1bb87d5f1-808837799.us-east-1.elb.amazonaws.com
  ```

* **CloudWatch Log Groups** (configured via `cloudwatch-configmap.yml`):

  * `/brain-tasks/nginx-access`
  * `/brain-tasks/nginx-error`

* **CodePipeline Status**:

  * Verified successful triggers from GitHub
  * CodeBuild builds and pushes Docker image to ECR
  * CodeDeploy deploys application to EKS
  * Logs are visible in CloudWatch

---

## 9. Learning Outcome

* Used AWS EKS to host a React application
* Dockerized and pushed image to ECR
* Automated build and deploy with CodePipeline and CodeBuild
* Delivered CI/CD integration with real YAML scripts
* Implemented log collection using CloudWatch Agent
