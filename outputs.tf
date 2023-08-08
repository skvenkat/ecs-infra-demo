output "cert_id" {
    value = aws_lb_listener.listener.certificate_arn
}

output "app_url" {
  value = aws_alb.app_load_balancer.dns_name
}