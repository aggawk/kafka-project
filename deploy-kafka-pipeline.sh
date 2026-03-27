#!/bin/bash
# =============================================================================
# deploy-kafka-pipeline.sh
# Deploys the Kafka pipeline in the correct dependency order.
# Usage: bash deploy-kafka-pipeline.sh
# =============================================================================

set -euo pipefail

NAMESPACE="java-microservices"

echo "=== Kafka Pipeline Deployment ==="
echo ""

# --- Step 0: Ensure namespace exists ---
echo "[0/6] Ensuring namespace '$NAMESPACE' exists..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
echo ""

# --- Step 1: Deploy Kafka StatefulSet and Services ---
echo "[1/6] Deploying Kafka StatefulSet and Services (kafka-headless + kafka-service)..."
kubectl apply -f kafka_advanced.yaml
echo "Applied kafka_advanced.yaml (brokers only — Kafka UI is deployed last)"
echo ""

# --- Step 2: Wait for all 3 broker pods to reach Running ---
echo "[2/6] Waiting for all 3 Kafka broker pods to be ready..."
kubectl rollout status statefulset/kafka -n $NAMESPACE --timeout=300s
echo "All 3 Kafka brokers are running."
echo ""

# --- Step 3: Run kafka-topic-init Job and wait for completion ---
echo "[3/6] Running kafka-topic-init Job..."
kubectl delete job kafka-topic-init -n $NAMESPACE --ignore-not-found
kubectl apply -f kafka_topic_job.yaml
echo "Waiting for topic init job to complete..."
kubectl wait --for=condition=complete job/kafka-topic-init -n $NAMESPACE --timeout=120s
echo "All topics created successfully."
echo ""

# --- Step 4: Deploy Order Consumer Deployment (3 replicas) ---
echo "[4/6] Deploying Order Consumer (3 replicas)..."
kubectl apply -f kafka_consumer_deployment.yaml
kubectl rollout status deployment/kafka-order-consumer -n $NAMESPACE --timeout=120s
echo "Order consumer deployment is ready."
echo ""

# --- Step 5: Run Order Producer Job ---
echo "[5/6] Running Order Producer Job..."
kubectl delete job kafka-order-producer -n $NAMESPACE --ignore-not-found
kubectl apply -f kafka_producer_job.yaml
echo "Waiting for producer job to complete..."
kubectl wait --for=condition=complete job/kafka-order-producer -n $NAMESPACE --timeout=120s
echo "Producer job completed."
kubectl logs job/kafka-order-producer -n $NAMESPACE --tail=5
echo ""

# --- Step 6: Deploy Kafka UI for operational visibility ---
echo "[6/6] Deploying Kafka UI..."
kubectl apply -f kafka_ui.yaml
kubectl rollout status deployment/kafka-ui -n $NAMESPACE --timeout=60s
echo "Kafka UI is available at NodePort 30005."
echo ""

echo "=== Deployment Complete ==="
echo ""
echo "Verify:"
echo "  kubectl get pods -n $NAMESPACE"
echo "  kubectl logs -f -l app=kafka-order-consumer -n $NAMESPACE"
echo "  Kafka UI: http://localhost:30005"
