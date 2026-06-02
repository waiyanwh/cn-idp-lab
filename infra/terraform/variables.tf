variable "cluster_name" {
  description = "Name of the local kind cluster used by the lab."
  type        = string
  default     = "cncf-idp"
}

variable "node_image" {
  description = "kind node image pinned to the Kubernetes version used by the lab."
  type        = string
  default     = "kindest/node:v1.34.0"
}
