# =============================================================================
# WindOH AWS Terraform — Outputs
# =============================================================================
# These are also defined inline in main.tf. This file provides a clean
# separation for CI/CD pipelines that consume outputs programmatically.
# =============================================================================

output "connection_command" {
  description = "SSH into the agent instance via Session Manager (no open SSH port needed)"
  value       = "aws ssm start-session --target ${aws_instance.agent.id} --region ${var.aws_region}"
}

output "agent_config_path" {
  description = "Path to agent config on the instance"
  value       = "/etc/windoh/config.toml"
}

output "agent_health_command" {
  description = "Check agent health via SSM Run Command"
  value       = "aws ssm send-command --instance-ids ${aws_instance.agent.id} --document-name AWS-RunShellScript --parameters 'commands=[\"/opt/windoh/wizard-aws status\"]' --region ${var.aws_region}"
}

output "cloudtrail_log_location" {
  description = "S3 path to CloudTrail logs"
  value       = "s3://${aws_s3_bucket.cloudtrail.bucket}/AWSLogs/${data.aws_caller_identity.current.account_id}/CloudTrail/"
}

output "agent_log_group" {
  description = "CloudWatch Logs group for agent stdout/stderr"
  value       = "/windoh/cloud-agent/${var.agent_id}"
}
