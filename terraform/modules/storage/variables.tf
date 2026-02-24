variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "environment" { type = string }
variable "tags" {
  type    = map(string)
  default = {}
}
variable "unique_suffix" { type = string }

variable "replication_type" {
  type    = string
  default = "LRS"
}

variable "create_private_endpoint" {
  type    = bool
  default = false
}

variable "pe_subnet_id" {
  type    = string
  default = ""
}

variable "storage_private_dns_zone_id" {
  type    = string
  default = ""
}
