# Azure Compute Gallery for golden images. Packer (images/dev-workstation) builds image VERSIONS into
# the image DEFINITION below; consumers (VMs, VM scale sets, AVD; Dev Box and Windows 365 consume
# images the same way) pick a version or "latest".

locals {
  tags = {
    project     = "platform-lab"
    environment = "lab"
    owner       = "platform-team"
    managed-by  = "terraform"
  }
}

resource "azurerm_resource_group" "images" {
  name     = "rg-platform-lab-images"
  location = var.location
  tags     = local.tags
}

resource "azurerm_shared_image_gallery" "lab" {
  name                = "gal_platformlab"
  resource_group_name = azurerm_resource_group.images.name
  location            = var.location
  description         = "Golden images built by Packer from images/"
  tags                = local.tags
}

# One definition per image "product"; versions (1.0.0, 1.0.1, ...) are added by each build.
resource "azurerm_shared_image" "dev_workstation" {
  name                = "dev-workstation-ws2025"
  gallery_name        = azurerm_shared_image_gallery.lab.name
  resource_group_name = azurerm_resource_group.images.name
  location            = var.location
  description         = "Developer workstation: Git, VS Code, Python, Azure CLI, Terraform, kubectl"
  os_type             = "Windows"
  hyper_v_generation  = "V2"
  architecture        = "x64"
  specialized         = false # generalized with sysprep: every VM gets its own identity

  # Security type "TrustedLaunch": images built on a Trusted Launch VM carry vTPM/secure-boot state,
  # which Azure only accepts into a TrustedLaunch definition (not "TrustedLaunchSupported").
  # VMs created from it must use Trusted Launch too.
  trusted_launch_enabled = true

  min_recommended_vcpu_count   = 2
  min_recommended_memory_in_gb = 8

  identifier {
    publisher = "platformlab"
    offer     = "dev-workstation"
    sku       = "ws2025"
  }

  tags = local.tags
}
