resource "kind_cluster" "main" {
  name           = var.cluster_name
  node_image     = var.node_image
  wait_for_ready = true
}

