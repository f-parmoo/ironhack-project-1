output "aurora_endpoint" {
  value = aws_rds_cluster.postgres.endpoint
}

output "redis_endpoint" {
  value = aws_lb.backend.dns_name
}