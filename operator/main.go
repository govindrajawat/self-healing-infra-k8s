package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
)

type Alert struct {
	Labels      map[string]string `json:"labels"`
	Annotations map[string]string `json:"annotations"`
	Status      string            `json:"status"`
	StartsAt    time.Time         `json:"startsAt"`
	EndsAt      time.Time         `json:"endsAt"`
}

type WebhookMessage struct {
	Alerts []Alert `json:"alerts"`
}

type RecoveryAction struct {
	Action    string
	Pod       string
	Namespace string
	App       string
	Reason    string
}

func main() {
	log.Println("🚀 Starting Self-Healing Operator...")
	
	http.HandleFunc("/webhook", handleWebhook)
	http.HandleFunc("/health", handleHealth)
	http.HandleFunc("/metrics", handleMetrics)
	
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	
	log.Printf("📡 Webhook server listening on port %s", port)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("healthy"))
}

func handleMetrics(w http.ResponseWriter, r *http.Request) {
	// Simple metrics endpoint for monitoring the operator itself
	metrics := fmt.Sprintf(`# HELP self_healing_operator_requests_total Total number of webhook requests
# TYPE self_healing_operator_requests_total counter
self_healing_operator_requests_total %d
`, 0) // In a real implementation, you'd track this metric
	
	w.Header().Set("Content-Type", "text/plain")
	w.Write([]byte(metrics))
}

func handleWebhook(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var msg WebhookMessage
	if err := json.NewDecoder(r.Body).Decode(&msg); err != nil {
		log.Printf("❌ Error decoding webhook payload: %v", err)
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	log.Printf("📨 Received %d alerts", len(msg.Alerts))

	for _, alert := range msg.Alerts {
		// Only process firing alerts
		if alert.Status != "firing" {
			continue
		}

		action := parseRecoveryAction(alert)
		if action == nil {
			log.Printf("⚠️  No recovery action found for alert: %s", alert.Labels["alertname"])
			continue
		}

		log.Printf("🔧 Executing recovery action: %s for %s/%s", action.Action, action.Namespace, action.Pod)
		
		success := executeRecoveryAction(*action)
		if success {
			log.Printf("✅ Recovery action completed successfully")
		} else {
			log.Printf("❌ Recovery action failed")
		}
	}

	w.WriteHeader(http.StatusOK)
	w.Write([]byte("OK"))
}

func parseRecoveryAction(alert Alert) *RecoveryAction {
	recoveryAction := alert.Labels["recovery_action"]
	if recoveryAction == "" {
		return nil
	}

	// Extract pod name from alert labels
	podName := alert.Labels["pod"]
	if podName == "" {
		podName = alert.Labels["kubernetes_pod_name"]
	}

	// Extract namespace
	namespace := alert.Labels["namespace"]
	if namespace == "" {
		namespace = alert.Labels["kubernetes_namespace"]
	}
	if namespace == "" {
		namespace = "default" // Default namespace
	}

	// Extract app name
	app := alert.Labels["app"]
	if app == "" {
		app = "unknown"
	}

	return &RecoveryAction{
		Action:    recoveryAction,
		Pod:       podName,
		Namespace: namespace,
		App:       app,
		Reason:    alert.Labels["alertname"],
	}
}

func executeRecoveryAction(action RecoveryAction) bool {
	config, err := rest.InClusterConfig()
	if err != nil {
		log.Printf("❌ Error getting in-cluster config: %v", err)
		return false
	}

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		log.Printf("❌ Error creating clientset: %v", err)
		return false
	}

	ctx := context.Background()

	switch action.Action {
	case "restart":
		return restartPod(ctx, clientset, action)
	case "redeploy":
		return redeployDeployment(ctx, clientset, action)
	case "scale":
		return scaleDeployment(ctx, clientset, action)
	default:
		log.Printf("⚠️  Unknown recovery action: %s", action.Action)
		return false
	}
}

func restartPod(ctx context.Context, clientset *kubernetes.Clientset, action RecoveryAction) bool {
	if action.Pod == "" {
		log.Printf("❌ No pod name provided for restart action")
		return false
	}

	log.Printf("🔄 Restarting pod %s/%s", action.Namespace, action.Pod)
	
	err := clientset.CoreV1().Pods(action.Namespace).Delete(ctx, action.Pod, metav1.DeleteOptions{})
	if err != nil {
		log.Printf("❌ Error deleting pod %s/%s: %v", action.Namespace, action.Pod, err)
		return false
	}

	log.Printf("✅ Successfully initiated restart of pod %s/%s", action.Namespace, action.Pod)
	return true
}

func redeployDeployment(ctx context.Context, clientset *kubernetes.Clientset, action RecoveryAction) bool {
	// Find deployment by app label
	deployments, err := clientset.AppsV1().Deployments(action.Namespace).List(ctx, metav1.ListOptions{
		LabelSelector: fmt.Sprintf("app=%s", action.App),
	})
	if err != nil {
		log.Printf("❌ Error listing deployments: %v", err)
		return false
	}

	if len(deployments.Items) == 0 {
		log.Printf("❌ No deployment found for app %s in namespace %s", action.App, action.Namespace)
		return false
	}

	deployment := deployments.Items[0]
	log.Printf("🔄 Redeploying deployment %s/%s", action.Namespace, deployment.Name)

	// Trigger rolling update by updating annotation
	if deployment.Spec.Template.Annotations == nil {
		deployment.Spec.Template.Annotations = make(map[string]string)
	}
	deployment.Spec.Template.Annotations["kubectl.kubernetes.io/restartedAt"] = time.Now().Format(time.RFC3339)

	_, err = clientset.AppsV1().Deployments(action.Namespace).Update(ctx, &deployment, metav1.UpdateOptions{})
	if err != nil {
		log.Printf("❌ Error updating deployment %s/%s: %v", action.Namespace, deployment.Name, err)
		return false
	}

	log.Printf("✅ Successfully initiated redeploy of deployment %s/%s", action.Namespace, deployment.Name)
	return true
}

func scaleDeployment(ctx context.Context, clientset *kubernetes.Clientset, action RecoveryAction) bool {
	// Find deployment by app label
	deployments, err := clientset.AppsV1().Deployments(action.Namespace).List(ctx, metav1.ListOptions{
		LabelSelector: fmt.Sprintf("app=%s", action.App),
	})
	if err != nil {
		log.Printf("❌ Error listing deployments: %v", err)
		return false
	}

	if len(deployments.Items) == 0 {
		log.Printf("❌ No deployment found for app %s in namespace %s", action.App, action.Namespace)
		return false
	}

	deployment := deployments.Items[0]
	currentReplicas := *deployment.Spec.Replicas
	newReplicas := currentReplicas + 1

	log.Printf("📈 Scaling deployment %s/%s from %d to %d replicas", action.Namespace, deployment.Name, currentReplicas, newReplicas)

	scale, err := clientset.AppsV1().Deployments(action.Namespace).GetScale(ctx, deployment.Name, metav1.GetOptions{})
	if err != nil {
		log.Printf("❌ Error getting scale for deployment %s/%s: %v", action.Namespace, deployment.Name, err)
		return false
	}

	scale.Spec.Replicas = int32(newReplicas)
	_, err = clientset.AppsV1().Deployments(action.Namespace).UpdateScale(ctx, deployment.Name, scale, metav1.UpdateOptions{})
	if err != nil {
		log.Printf("❌ Error scaling deployment %s/%s: %v", action.Namespace, deployment.Name, err)
		return false
	}

	log.Printf("✅ Successfully scaled deployment %s/%s to %d replicas", action.Namespace, deployment.Name, newReplicas)
	return true
}