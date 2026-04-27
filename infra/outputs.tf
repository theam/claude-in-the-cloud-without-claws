output "instance_name" {
  description = "Lightsail instance name"
  value       = aws_lightsail_instance.coder.name
}

output "static_ip" {
  description = "Static IP address — point your DNS A record here"
  value       = aws_lightsail_static_ip.coder.ip_address
}

output "dashboard_url" {
  description = "Coder dashboard URL (once DNS A record points to static_ip and TLS is provisioned)"
  value       = "https://${var.domain}"
}

output "dns_instruction" {
  description = "DNS step required after apply"
  value       = "Point an A record for ${var.domain} → ${aws_lightsail_static_ip.coder.ip_address}"
}
