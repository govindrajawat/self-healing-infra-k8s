package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"sync"
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

// cooldown: skip recovery if the same app just had an action in the last 3 minutes.
// This prevents alert→restart→alert→restart infinite loops.
var (
	cooldownMu   sync.Mutex
	lastAction   = map[string]time.Time{} // key = "namespace/app"
	cooldownTime = 3 * time.Minute
)

// recoveries tracks total actions taken, printed on each webhook call
var (
	recoveryMu    sync.Mutex
	recoveryCount = map[string]int{}
)

func isCoolingDown(key string) bool {
	cooldownMu.Lock()
	defer cooldownMu.Unlock()
	last, ok := lastAction[key]
	return ok && time.Since(last) < cooldownTime
}

func recordCooldown(key string) {
	cooldownMu.Lock()
	defer cooldownMu.Unlock()
	lastAction[key] = time.Now()
}

func recordRecovery(action string) {
	recoveryMu.Lock()
	defer recoveryMu.Unlock()
	recoveryCount[action]++
	log.Printf("Recovery totals — restart:%d redeploy:%d scale:%d",
		recoveryCount["restart"], recoveryCount["redeploy"], recoveryCount["scale"])
}

func main() {
	log.Println("Starting Self-Healing Operator...")

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

	// Limit request body to 1MB to protect against large/malicious payloads
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)

	var msg WebhookMessage
	if err := json.NewDecoder(r.Body).Decode(&msg); err != nil {
		log.Printf("Error decoding webhook payload: %v", err)
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	log.Printf("Received %d alert(s)", len(msg.Alerts))

	for _, alert := range msg.Alerts {
		if alert.Status != "firing" {
			continue
		}

		action := parseRecoveryAction(alert)
		if action == nil {
			log.Printf("No recovery_action label on alert: %s", alert.Labels["alertname"])
			continue
		}

		// Cooldown check — skip if this app was just acted on
		cooldownKey := action.Namespace + "/" + action.App
		if isCoolingDown(cooldownKey) {
			log.Printf("Skipping '%s' for %s — cooldown active (last action within %s)",
				action.Action, cooldownKey, cooldownTime)
			continue
		}

		log.Printf("Executing '%s' for alert '%s' (app: %s/%s, pod: %s)",
			action.Action, action.AlertName, action.Namespace, action.App, action.Pod)

		if err := executeRecoveryAction(action); err != nil {
			log.Printf("Recovery action failed: %v", err)
		} else {
			log.Printf("Recovery action '%s' completed OK", action.Action)
			recordCooldown(cooldownKey)
			recordRecovery(action.Action)
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
		namespace = "default"
	}

	return &RecoveryAction{
		Action:    recoveryAction,
		Pod:       alert.Labels["pod"],
		Namespace: namespace,
		App:       alert.Labels["app"],
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

// restartPod deletes the pod - Kubernetes recreates it via the ReplicaSet
func restartPod(ctx context.Context, action *RecoveryAction) error {
	if action.Pod == "" {
		return fmt.Errorf("no pod name in alert labels for restart action")
	}

	log.Printf("Deleting pod %s/%s", action.Namespace, action.Pod)
	err := clientset.CoreV1().Pods(action.Namespace).Delete(ctx, action.Pod, metav1.DeleteOptions{})
	if err != nil {
		return fmt.Errorf("failed to delete pod %s/%s: %v", action.Namespace, action.Pod, err)
	}
	log.Printf("Pod %s/%s deleted — Kubernetes will recreate it", action.Namespace, action.Pod)
	return nil
}

// redeployDeployment triggers a rolling restart by bumping an annotation
func redeployDeployment(ctx context.Context, action *RecoveryAction) error {
	deployments, err := clientset.AppsV1().Deployments(action.Namespace).List(ctx, metav1.ListOptions{
		LabelSelector: "app=" + action.App,
	})
	if err != nil {
		return fmt.Errorf("failed to list deployments: %v", err)
	}
	if len(deployments.Items) == 0 {
		return fmt.Errorf("no deployment with label app=%s in namespace %s", action.App, action.Namespace)
	}

	dep := deployments.Items[0]
	if dep.Spec.Template.Annotations == nil {
		dep.Spec.Template.Annotations = make(map[string]string)
	}
	dep.Spec.Template.Annotations["kubectl.kubernetes.io/restartedAt"] = time.Now().Format(time.RFC3339)

	_, err = clientset.AppsV1().Deployments(action.Namespace).Update(ctx, &dep, metav1.UpdateOptions{})
	if err != nil {
		return fmt.Errorf("failed to update deployment %s/%s: %v", action.Namespace, dep.Name, err)
	}
	log.Printf("Rolling restart triggered for deployment %s/%s", action.Namespace, dep.Name)
	return nil
}

// scaleDeployment adds one replica to the deployment
func scaleDeployment(ctx context.Context, action *RecoveryAction) error {
	deployments, err := clientset.AppsV1().Deployments(action.Namespace).List(ctx, metav1.ListOptions{
		LabelSelector: "app=" + action.App,
	})
	if err != nil {
		return fmt.Errorf("failed to list deployments: %v", err)
	}
	if len(deployments.Items) == 0 {
		return fmt.Errorf("no deployment with label app=%s in namespace %s", action.App, action.Namespace)
	}

	dep := deployments.Items[0]

	currentReplicas := int32(1)
	if dep.Spec.Replicas != nil {
		currentReplicas = *dep.Spec.Replicas
	}
	newReplicas := currentReplicas + 1

	scale, err := clientset.AppsV1().Deployments(action.Namespace).GetScale(ctx, dep.Name, metav1.GetOptions{})
	if err != nil {
		return fmt.Errorf("failed to get scale for %s/%s: %v", action.Namespace, dep.Name, err)
	}

	scale.Spec.Replicas = newReplicas
	_, err = clientset.AppsV1().Deployments(action.Namespace).UpdateScale(ctx, dep.Name, scale, metav1.UpdateOptions{})
	if err != nil {
		return fmt.Errorf("failed to scale %s/%s: %v", action.Namespace, dep.Name, err)
	}
	log.Printf("Deployment %s/%s scaled %d -> %d replicas", action.Namespace, dep.Name, currentReplicas, newReplicas)
	return nil
}