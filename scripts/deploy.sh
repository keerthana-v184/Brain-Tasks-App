#!/bin/bash

kubectl apply -f cloudwatch-configmap.yml
kubectl apply -f deployment.yml
kubectl apply -f service.yml

