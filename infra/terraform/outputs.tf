output "cluster_name" {
  description = "Name of the kind cluster."
  value       = kind_cluster.main.name
}

output "endpoint" {
  description = "Kubernetes API endpoint for the kind cluster."
  value       = kind_cluster.main.endpoint
}

