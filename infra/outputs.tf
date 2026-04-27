output "instance_name" {
  description = "Lightsail instance name"
  value       = aws_lightsail_instance.coder.name
}

output "static_ip" {
  description = "Static IP address — point your DNS A record here"
  value       = aws_lightsail_static_ip.coder.ip_address
}

output "dashboard_url" {
  description = "Coder dashboard (once DNS and TLS are ready)"
  value       = "https://software.theagilemonkeys.com"
}
