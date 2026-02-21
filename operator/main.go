package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
)

// Alert represents a single Alertmanager alert
type Alert struct {
	Labels      map[string]string `json:"labels"`
	Annotations map[string]string `json:"annotations"`
	Status      string            `json:"status"`
}

// WebhookMessage is the payload sent by Alertmanager
type WebhookMessage struct {
	Alerts []Alert `json:"alerts"`
}

// RecoveryAction holds the parsed action details from an alert
type RecoveryAction struct {
	Action    string
	Pod       string
	Namespace string
	App       string
	AlertName string
}

// global k8s client - created once at startup
var clientset *kubernetes.Clientset

func main() {
	log.Println("Starting Self-Healing Operator...")

	// Connect to the Kubernetes cluster using in-cluster config
	config, err := rest.InClusterConfig()
	if err != nil {
		log.Fatalf("Failed to get in-cluster config: %v", err)
	}

	clientset, err = kubernetes.NewForConfig(config)
	if err != nil {
		log.Fatalf("Failed to create Kubernetes client: %v", err)
	}

	log.Println("Connected to Kubernetes cluster")

	http.HandleFunc("/webhook", handleWebhook)
	http.HandleFunc("/health", handleHealth)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("Listening on port %s", port)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("healthy"))
}

func handleWebhook(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var msg WebhookMessage
	if err := json.NewDecoder(r.Body).Decode(&msg); err != nil {
		log.Printf("Error decoding webhook payload: %v", err)
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	log.Printf("Received %d alert(s)", len(msg.Alerts))

	for _, alert := range msg.Alerts {
		// Only act on firing alerts
		if alert.Status != "firing" {
			continue
		}

		action := parseRecoveryAction(alert)
		if action == nil {
			log.Printf("No recovery_action label on alert: %s", alert.Labels["alertname"])
			continue
		}

		log.Printf("Executing recovery action '%s' for alert '%s' (namespace: %s, pod: %s)",
			action.Action, action.AlertName, action.Namespace, action.Pod)

		if err := executeRecoveryAction(action); err != nil {
			log.Printf("Recovery action failed: %v", err)
		} else {
			log.Printf("Recovery action '%s' completed successfully", action.Action)
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

	namespace := alert.Labels["namespace"]
	if namespace == "" {
		namespace = alert.Labels["kubernetes_namespace"]
	}
	if namespace == "" {
		namespace = "default"
	}

	pod := alert.Labels["pod"]
	if pod == "" {
		pod = alert.Labels["kubernetes_pod_name"]
	}

	app := alert.Labels["app"]
	if app == "" {
		app = "unknown"
	}

	return &RecoveryAction{
		Action:    recoveryAction,
		Pod:       pod,
		Namespace: namespace,
		App:       app,
		AlertName: alert.Labels["alertname"],
	}
}

func executeRecoveryAction(action *RecoveryAction) error {
	ctx := context.Background()

	switch action.Action {
	case "restart":
		return restartPod(ctx, action)
	case "redeploy":
		return redeployDeployment(ctx, action)
	case "scale":
		return scaleDeployment(ctx, action)
	default:
		return fmt.Errorf("unknown recovery action: %s", action.Action)
	}
}

// restartPod deletes the pod so Kubernetes recreates it
func restartPod(ctx context.Context, action *RecoveryAction) error {
	if action.Pod == "" {
		return fmt.Errorf("no pod name in alert labels for restart action")
	}

	log.Printf("Restarting pod %s/%s", action.Namespace, action.Pod)

	err := clientset.CoreV1().Pods(action.Namespace).Delete(ctx, action.Pod, metav1.DeleteOptions{})
	if err != nil {
		return fmt.Errorf("failed to delete pod %s/%s: %v", action.Namespace, action.Pod, err)
	}

	log.Printf("Pod %s/%s deleted - Kubernetes will restart it", action.Namespace, action.Pod)
	return nil
}

// redeployDeployment triggers a rolling restart by updating an annotation
func redeployDeployment(ctx context.Context, action *RecoveryAction) error {
	deployments, err := clientset.AppsV1().Deployments(action.Namespace).List(ctx, metav1.ListOptions{
		LabelSelector: fmt.Sprintf("app=%s", action.App),
	})
	if err != nil {
		return fmt.Errorf("failed to list deployments: %v", err)
	}

	if len(deployments.Items) == 0 {
		return fmt.Errorf("no deployment found with label app=%s in namespace %s", action.App, action.Namespace)
	}

	deployment := deployments.Items[0]
	log.Printf("Triggering rolling restart of deployment %s/%s", action.Namespace, deployment.Name)

	if deployment.Spec.Template.Annotations == nil {
		deployment.Spec.Template.Annotations = make(map[string]string)
	}
	deployment.Spec.Template.Annotations["kubectl.kubernetes.io/restartedAt"] = time.Now().Format(time.RFC3339)

	_, err = clientset.AppsV1().Deployments(action.Namespace).Update(ctx, &deployment, metav1.UpdateOptions{})
	if err != nil {
		return fmt.Errorf("failed to update deployment %s/%s: %v", action.Namespace, deployment.Name, err)
	}

	log.Printf("Rolling restart triggered for deployment %s/%s", action.Namespace, deployment.Name)
	return nil
}

// scaleDeployment adds one more replica to the deployment
func scaleDeployment(ctx context.Context, action *RecoveryAction) error {
	deployments, err := clientset.AppsV1().Deployments(action.Namespace).List(ctx, metav1.ListOptions{
		LabelSelector: fmt.Sprintf("app=%s", action.App),
	})
	if err != nil {
		return fmt.Errorf("failed to list deployments: %v", err)
	}

	if len(deployments.Items) == 0 {
		return fmt.Errorf("no deployment found with label app=%s in namespace %s", action.App, action.Namespace)
	}

	deployment := deployments.Items[0]

	// Safe nil check: default to 1 if Replicas pointer is nil
	currentReplicas := int32(1)
	if deployment.Spec.Replicas != nil {
		currentReplicas = *deployment.Spec.Replicas
	}
	newReplicas := currentReplicas + 1

	log.Printf("Scaling deployment %s/%s: %d -> %d replicas", action.Namespace, deployment.Name, currentReplicas, newReplicas)

	scale, err := clientset.AppsV1().Deployments(action.Namespace).GetScale(ctx, deployment.Name, metav1.GetOptions{})
	if err != nil {
		return fmt.Errorf("failed to get scale for deployment %s/%s: %v", action.Namespace, deployment.Name, err)
	}

	scale.Spec.Replicas = newReplicas
	_, err = clientset.AppsV1().Deployments(action.Namespace).UpdateScale(ctx, deployment.Name, scale, metav1.UpdateOptions{})
	if err != nil {
		return fmt.Errorf("failed to scale deployment %s/%s: %v", action.Namespace, deployment.Name, err)
	}

	log.Printf("Deployment %s/%s scaled to %d replicas", action.Namespace, deployment.Name, newReplicas)
	return nil
}