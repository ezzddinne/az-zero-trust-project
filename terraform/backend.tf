# Remote state stored in Azure Blob Storage with encryption and locking.
# The storage account is created by scripts/bootstrap.sh before first terraform init.

terraform {
  backend "azurerm" {
    # These values are injected per-environment via backend config files:
    #   terraform init -backend-config=environments/<env>/backend.hcl
    #
    # resource_group_name  = "rg-zt-tfstate"
    # storage_account_name = "stztstate<unique>"
    # container_name       = "tfstate"
    # key                  = "<env>.terraform.tfstate"
    #
    # Security controls:
    # - Blob versioning enabled (state history)
    # - Azure Blob lease-based locking (prevents concurrent writes)
    # - Storage account encryption at rest (AES-256)
    # - No public blob access
    # - HTTPS only
  }
}
