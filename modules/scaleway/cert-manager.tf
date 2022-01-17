locals {

  cert-manager = merge(
    local.helm_defaults,
    {
      name                      = local.helm_dependencies[index(local.helm_dependencies.*.name, "cert-manager")].name
      chart                     = local.helm_dependencies[index(local.helm_dependencies.*.name, "cert-manager")].name
      repository                = local.helm_dependencies[index(local.helm_dependencies.*.name, "cert-manager")].repository
      chart_version             = local.helm_dependencies[index(local.helm_dependencies.*.name, "cert-manager")].version
      namespace                 = "cert-manager"
      service_account_name      = "cert-manager"
      enabled                   = false
      acme_email                = "contact@acme.com"
      acme_http01_enabled       = false
      acme_http01_ingress_class = ""
      acme_dns01_enabled        = false
      allowed_cidrs             = ["0.0.0.0/0"]
      csi_driver                = false
    },
    var.cert-manager
  )

  cert-manager_scaleway_webhook_dns = merge(
    local.helm_defaults,
    {
      name          = local.helm_dependencies[index(local.helm_dependencies.*.name, "scaleway-webhook")].name
      chart         = local.helm_dependencies[index(local.helm_dependencies.*.name, "scaleway-webhook")].name
      repository    = local.helm_dependencies[index(local.helm_dependencies.*.name, "scaleway-webhook")].repository
      chart_version = local.helm_dependencies[index(local.helm_dependencies.*.name, "scaleway-webhook")].version
      enabled       = local.cert-manager["acme_dns01_enabled"] && local.cert-manager["enabled"]
      secret_name   = "scaleway-credentials"
    },
    var.cert-manager_scaleway_webhook_dns
  )

  values_cert-manager = <<VALUES
global:
  podSecurityPolicy:
    enabled: true
    useAppArmor: false
  priorityClassName: ${local.priority-class["create"] ? kubernetes_priority_class.kubernetes_addons[0].metadata[0].name : ""}
serviceAccount:
  name: ${local.cert-manager["service_account_name"]}
prometheus:
  servicemonitor:
    enabled: ${local.kube-prometheus-stack["enabled"] || local.victoria-metrics-k8s-stack["enabled"]}
securityContext:
  fsGroup: 1001
installCRDs: true
VALUES

}

resource "kubernetes_namespace" "cert-manager" {
  count = local.cert-manager["enabled"] ? 1 : 0

  metadata {
    annotations = {
      "certmanager.k8s.io/disable-validation" = "true"
    }

    labels = {
      name = local.cert-manager["namespace"]
    }

    name = local.cert-manager["namespace"]
  }
}

resource "helm_release" "cert-manager" {
  count                 = local.cert-manager["enabled"] ? 1 : 0
  repository            = local.cert-manager["repository"]
  name                  = local.cert-manager["name"]
  chart                 = local.cert-manager["chart"]
  version               = local.cert-manager["chart_version"]
  timeout               = local.cert-manager["timeout"]
  force_update          = local.cert-manager["force_update"]
  recreate_pods         = local.cert-manager["recreate_pods"]
  wait                  = local.cert-manager["wait"]
  atomic                = local.cert-manager["atomic"]
  cleanup_on_fail       = local.cert-manager["cleanup_on_fail"]
  dependency_update     = local.cert-manager["dependency_update"]
  disable_crd_hooks     = local.cert-manager["disable_crd_hooks"]
  disable_webhooks      = local.cert-manager["disable_webhooks"]
  render_subchart_notes = local.cert-manager["render_subchart_notes"]
  replace               = local.cert-manager["replace"]
  reset_values          = local.cert-manager["reset_values"]
  reuse_values          = local.cert-manager["reuse_values"]
  skip_crds             = local.cert-manager["skip_crds"]
  verify                = local.cert-manager["verify"]
  values = [
    local.values_cert-manager,
    local.cert-manager["extra_values"]
  ]
  namespace = kubernetes_namespace.cert-manager.*.metadata.0.name[count.index]

  depends_on = [
    helm_release.kube-prometheus-stack
  ]
}

resource "helm_release" "scaleway-webhook-dns" {
  count                 = local.cert-manager_scaleway_webhook_dns["enabled"] ? 1 : 0
  repository            = local.cert-manager_scaleway_webhook_dns["repository"]
  name                  = local.cert-manager_scaleway_webhook_dns["name"]
  chart                 = local.cert-manager_scaleway_webhook_dns["chart"]
  version               = local.cert-manager_scaleway_webhook_dns["chart_version"]
  timeout               = local.cert-manager_scaleway_webhook_dns["timeout"]
  force_update          = local.cert-manager_scaleway_webhook_dns["force_update"]
  recreate_pods         = local.cert-manager_scaleway_webhook_dns["recreate_pods"]
  wait                  = local.cert-manager_scaleway_webhook_dns["wait"]
  atomic                = local.cert-manager_scaleway_webhook_dns["atomic"]
  cleanup_on_fail       = local.cert-manager_scaleway_webhook_dns["cleanup_on_fail"]
  dependency_update     = local.cert-manager_scaleway_webhook_dns["dependency_update"]
  disable_crd_hooks     = local.cert-manager_scaleway_webhook_dns["disable_crd_hooks"]
  disable_webhooks      = local.cert-manager_scaleway_webhook_dns["disable_webhooks"]
  render_subchart_notes = local.cert-manager_scaleway_webhook_dns["render_subchart_notes"]
  replace               = local.cert-manager_scaleway_webhook_dns["replace"]
  reset_values          = local.cert-manager_scaleway_webhook_dns["reset_values"]
  reuse_values          = local.cert-manager_scaleway_webhook_dns["reuse_values"]
  skip_crds             = local.cert-manager_scaleway_webhook_dns["skip_crds"]
  verify                = local.cert-manager_scaleway_webhook_dns["verify"]
  values                = []
  namespace             = kubernetes_namespace.cert-manager.*.metadata.0.name[count.index]

  depends_on = [
    helm_release.kube-prometheus-stack,
    helm_release.cert-manager,
    time_sleep.cert-manager_sleep
  ]
}

resource "kubernetes_secret" "scaleway_credentials" {
  count = local.cert-manager_scaleway_webhook_dns["enabled"] ? 1 : 0
  metadata {
    name      = local.cert-manager_scaleway_webhook_dns["secret_name"]
    namespace = local.cert-manager["namespace"]
  }
  data = {
    SCW_ACCESS_KEY = local.scaleway["scw_access_key"]
    SCW_SECRET_KEY = local.scaleway["scw_secret_key"]
  }
}

data "kubectl_path_documents" "cert-manager_cluster_issuers" {
  pattern = "${path.module}/templates/cert-manager-cluster-issuers.yaml.tpl"
  vars = {
    acme_email                = local.cert-manager["acme_email"]
    acme_http01_enabled       = local.cert-manager["acme_http01_enabled"]
    acme_http01_ingress_class = local.cert-manager["acme_http01_ingress_class"]
    acme_dns01_enabled        = local.cert-manager["acme_dns01_enabled"]
    secret_name               = local.cert-manager_scaleway_webhook_dns["secret_name"]
  }
}

resource "time_sleep" "cert-manager_sleep" {
  count           = local.cert-manager["enabled"] && (local.cert-manager["acme_http01_enabled"] || local.cert-manager["acme_dns01_enabled"]) ? 1 : 0
  depends_on      = [helm_release.cert-manager]
  create_duration = "120s"
}

resource "kubectl_manifest" "cert-manager_cluster_issuers" {
  count     = local.cert-manager["enabled"] && (local.cert-manager["acme_http01_enabled"] || local.cert-manager["acme_dns01_enabled"]) ? length(data.kubectl_path_documents.cert-manager_cluster_issuers.documents) : 0
  yaml_body = element(data.kubectl_path_documents.cert-manager_cluster_issuers.documents, count.index)
  depends_on = [
    helm_release.cert-manager,
    kubernetes_namespace.cert-manager,
    time_sleep.cert-manager_sleep
  ]
}