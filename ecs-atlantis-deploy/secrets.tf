resource "aws_ssm_parameter" "github_token" {
  name        = "/atlantis/github_token"
  description = "GitHub PAT for Atlantis"
  type        = "SecureString"
  value       = "CHANGE_ME"

  # We use lifecycle ignore_changes so Terraform doesn't overwrite 
  # the real secret after you manually update it in the AWS Console.
  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "webhook_secret" {
  name        = "/atlantis/webhook_secret"
  description = "GitHub Webhook Secret for Atlantis"
  type        = "SecureString"
  value       = "CHANGE_ME"

  lifecycle {
    ignore_changes = [value]
  }
}
