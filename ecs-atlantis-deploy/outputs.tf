output "atlantis_url" {
  description = "The public URL to access Atlantis and configure as your GitHub Webhook"
  value       = "http://${aws_lb.atlantis.dns_name}"
}
