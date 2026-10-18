output "resource_group" {
  value = azurerm_resource_group.images.name
}

output "gallery_name" {
  value = azurerm_shared_image_gallery.lab.name
}

output "image_definition" {
  value = azurerm_shared_image.dev_workstation.name
}
