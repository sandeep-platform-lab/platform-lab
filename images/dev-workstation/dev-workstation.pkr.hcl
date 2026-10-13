# Golden developer workstation image, built as code.
#   packer init . && packer build -var subscription_id=$(az account show --query id -o tsv) -var image_version=1.0.0 .
# Output: a new version of dev-workstation-ws2025 in gal_platformlab (terraform/azure-images).

packer {
  required_plugins {
    azure = {
      source  = "github.com/hashicorp/azure"
      version = "~> 2"
    }
  }
}

variable "subscription_id" {
  type = string
}

variable "image_version" {
  type        = string
  description = "Semantic version of this build, e.g. 1.0.0. Each build adds a new version; consumers pin or use latest."
}

variable "location" {
  type    = string
  default = "switzerlandnorth"
}

variable "vm_size" {
  type    = string
  default = "Standard_B2ms" # this subscription has B-series quota in Switzerland North
}

variable "gallery_resource_group" {
  type    = string
  default = "rg-platform-lab-images"
}

variable "gallery_name" {
  type    = string
  default = "gal_platformlab"
}

variable "image_name" {
  type    = string
  default = "dev-workstation-ws2025"
}

source "azure-arm" "dev_workstation" {
  use_azure_cli_auth = true
  subscription_id    = var.subscription_id
  location           = var.location
  vm_size            = var.vm_size

  # Licence included in the VM price. For Dev Box / Windows 365 you'd use a Windows 11 Enterprise
  # image, which needs an eligible licence (e.g. Microsoft 365 E3/E5 or Business Premium).
  os_type         = "Windows"
  image_publisher = "MicrosoftWindowsServer"
  image_offer     = "WindowsServer"
  image_sku       = "2025-datacenter-azure-edition-smalldisk" # 30 GB OS disk: cheaper to store per version

  # Trusted Launch: secure boot + virtual TPM, the current baseline.
  security_type       = "TrustedLaunch"
  secure_boot_enabled = true
  vtpm_enabled        = true

  communicator   = "winrm"
  winrm_use_ssl  = true
  winrm_insecure = true
  winrm_timeout  = "20m"
  winrm_username = "packer"

  shared_image_gallery_destination {
    subscription         = var.subscription_id
    resource_group       = var.gallery_resource_group
    gallery_name         = var.gallery_name
    image_name           = var.image_name
    image_version        = var.image_version
    replication_regions  = [var.location]
    storage_account_type = "Standard_LRS"
  }

  azure_tags = {
    project       = "platform-lab"
    managed-by    = "packer"
    image-name    = var.image_name
    image-version = var.image_version
  }
}

build {
  sources = ["source.azure-arm.dev_workstation"]

  provisioner "powershell" {
    script = "${path.root}/scripts/install-dev-tools.ps1"
  }

  provisioner "windows-restart" {
    restart_timeout = "15m"
  }

  # Generalize: remove machine-specific identity so every VM built from the image is unique.
  # (Microsoft's documented Packer sequence for Azure Windows images.)
  provisioner "powershell" {
    inline = [
      "while ((Get-Service RdAgent).Status -ne 'Running') { Start-Sleep -s 5 }",
      "while ((Get-Service WindowsAzureGuestAgent).Status -ne 'Running') { Start-Sleep -s 5 }",
      "& $env:SystemRoot\\System32\\Sysprep\\Sysprep.exe /oobe /generalize /quiet /quit /mode:vm",
      "while ($true) { $s = (Get-ItemProperty HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Setup\\State).ImageState; if ($s -ne 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') { Write-Output $s; Start-Sleep -s 10 } else { break } }"
    ]
  }
}
