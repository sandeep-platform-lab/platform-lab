package controller

import (
	"context"

	corev1 "k8s.io/api/core/v1"
	rbacv1 "k8s.io/api/rbac/v1"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	logf "sigs.k8s.io/controller-runtime/pkg/log"

	platformv1alpha1 "example.com/teamspace-operator/api/v1alpha1"
)

// TeamSpaceReconciler turns one TeamSpace into a ready-to-use team namespace:
// Namespace (Pod Security restricted) + ResourceQuota + RoleBinding for the team's admin group.
type TeamSpaceReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=platform.example.com,resources=teamspaces,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=platform.example.com,resources=teamspaces/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=platform.example.com,resources=teamspaces/finalizers,verbs=update
// +kubebuilder:rbac:groups="",resources=namespaces;resourcequotas,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=rbac.authorization.k8s.io,resources=rolebindings,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=rbac.authorization.k8s.io,resources=clusterroles,verbs=bind,resourceNames=admin

// Reconcile compares desired state (the TeamSpace) with actual state and closes the gap.
// It must be idempotent: it runs on every change, on every restart, and on every resync.
func (r *TeamSpaceReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	log := logf.FromContext(ctx)

	// 1. Read desired state. NotFound = it was deleted; owner references let the garbage collector
	//    remove what we created, so there is nothing to do.
	var ts platformv1alpha1.TeamSpace
	if err := r.Get(ctx, req.NamespacedName, &ts); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}
	nsName := "team-" + ts.Name

	// 2. Namespace. CreateOrUpdate = get, mutate, then create or update only if something changed.
	ns := &corev1.Namespace{ObjectMeta: metav1.ObjectMeta{Name: nsName}}
	if _, err := controllerutil.CreateOrUpdate(ctx, r.Client, ns, func() error {
		if ns.Labels == nil {
			ns.Labels = map[string]string{}
		}
		ns.Labels["pod-security.kubernetes.io/enforce"] = "restricted"
		ns.Labels["platform.example.com/team"] = ts.Name
		return controllerutil.SetControllerReference(&ts, ns, r.Scheme)
	}); err != nil {
		return r.fail(ctx, &ts, "NamespaceFailed", err)
	}

	// 3. ResourceQuota from the spec.
	quota := &corev1.ResourceQuota{ObjectMeta: metav1.ObjectMeta{Name: "team-quota", Namespace: nsName}}
	if _, err := controllerutil.CreateOrUpdate(ctx, r.Client, quota, func() error {
		quota.Spec.Hard = corev1.ResourceList{
			corev1.ResourceRequestsCPU:    ts.Spec.CPU,
			corev1.ResourceRequestsMemory: ts.Spec.Memory,
		}
		return controllerutil.SetControllerReference(&ts, quota, r.Scheme)
	}); err != nil {
		return r.fail(ctx, &ts, "QuotaFailed", err)
	}

	// 4. RoleBinding: the team's group gets the built-in "admin" ClusterRole, only in its namespace.
	rb := &rbacv1.RoleBinding{ObjectMeta: metav1.ObjectMeta{Name: "team-admins", Namespace: nsName}}
	if _, err := controllerutil.CreateOrUpdate(ctx, r.Client, rb, func() error {
		rb.RoleRef = rbacv1.RoleRef{APIGroup: rbacv1.GroupName, Kind: "ClusterRole", Name: "admin"}
		rb.Subjects = []rbacv1.Subject{{APIGroup: rbacv1.GroupName, Kind: rbacv1.GroupKind, Name: ts.Spec.AdminGroup}}
		return controllerutil.SetControllerReference(&ts, rb, r.Scheme)
	}); err != nil {
		return r.fail(ctx, &ts, "RoleBindingFailed", err)
	}

	// 5. Report observed state.
	ts.Status.Namespace = nsName
	meta.SetStatusCondition(&ts.Status.Conditions, metav1.Condition{
		Type: "Ready", Status: metav1.ConditionTrue, Reason: "Reconciled",
		Message: "namespace " + nsName + " is ready", ObservedGeneration: ts.Generation,
	})
	if err := r.Status().Update(ctx, &ts); err != nil {
		return ctrl.Result{}, err // a conflict here just means: requeue and try again
	}
	log.Info("reconciled", "teamspace", ts.Name, "namespace", nsName)
	return ctrl.Result{}, nil
}

// fail records the error in a condition and returns it, so controller-runtime retries with backoff.
func (r *TeamSpaceReconciler) fail(ctx context.Context, ts *platformv1alpha1.TeamSpace, reason string, err error) (ctrl.Result, error) {
	meta.SetStatusCondition(&ts.Status.Conditions, metav1.Condition{
		Type: "Ready", Status: metav1.ConditionFalse, Reason: reason, Message: err.Error(), ObservedGeneration: ts.Generation,
	})
	_ = r.Status().Update(ctx, ts)
	return ctrl.Result{}, err
}

// SetupWithManager: watch TeamSpaces, and also the objects we own, so that deleting or editing
// the quota by hand triggers a reconcile that puts it back (self-healing, like Argo CD).
func (r *TeamSpaceReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&platformv1alpha1.TeamSpace{}).
		Owns(&corev1.Namespace{}).
		Owns(&corev1.ResourceQuota{}).
		Owns(&rbacv1.RoleBinding{}).
		Named("teamspace").
		Complete(r)
}
