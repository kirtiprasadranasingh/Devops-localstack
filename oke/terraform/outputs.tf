output "cluster_id" {
  value = oci_containerengine_cluster.main.id
}

output "cluster_name" {
  value = var.cluster_name
}

output "region" {
  value = var.region
}

output "ocir_namespace" {
  description = "Tenancy namespace for OCIR (used in image paths)"
  value       = data.oci_objectstorage_namespace.ns.namespace
}

output "ocir_fastapi_repo" {
  value = "${var.region}.ocir.io/${data.oci_objectstorage_namespace.ns.namespace}/${oci_artifacts_container_repository.fastapi.display_name}"
}

output "ocir_console_repo" {
  value = "${var.region}.ocir.io/${data.oci_objectstorage_namespace.ns.namespace}/${oci_artifacts_container_repository.console.display_name}"
}

output "configure_kubectl" {
  value = "oci ce cluster create-kubeconfig --cluster-id ${oci_containerengine_cluster.main.id} --file $env:USERPROFILE\\.kube\\config --region ${var.region} --token-version 2.0.0 --kube-endpoint PUBLIC_ENDPOINT"
}

output "next_steps" {
  value = <<-EOT
    1. oci ce cluster create-kubeconfig --cluster-id ${oci_containerengine_cluster.main.id} --region ${var.region}
    2. kubectl get nodes
    3. cd ..\\scripts && .\\04-install-platform.ps1
    4. .\\05-push-images.ps1
    5. kubectl apply -f ..\\manifests\\
  EOT
}

data "oci_objectstorage_namespace" "ns" {
  compartment_id = var.compartment_id
}
