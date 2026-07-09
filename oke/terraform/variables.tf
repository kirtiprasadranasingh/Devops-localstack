variable "compartment_id" {
  type        = string
  description = "OCI compartment OCID"
}

variable "region" {
  type        = string
  default     = "ap-mumbai-1"
  description = "OCI region — must have A1 capacity (try ap-mumbai-1, ap-hyderabad-1, uk-london-1)"
}

variable "cluster_name" {
  type    = string
  default = "devopslocalstack"
}

variable "kubernetes_version" {
  type    = string
  default = "v1.30.1"
}

variable "vcn_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "node_count" {
  type    = number
  default = 1
}

variable "node_ocpus" {
  type    = number
  default = 2
}

variable "node_memory_gbs" {
  type    = number
  default = 12
}
