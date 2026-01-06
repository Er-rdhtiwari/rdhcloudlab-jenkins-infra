output "instance_id" {
  description = "Jenkins EC2 instance ID"
  value       = aws_instance.jenkins.id
}

output "elastic_ip" {
  description = "Elastic IP address for Jenkins"
  value       = aws_eip.jenkins.public_ip
}

output "jenkins_fqdn" {
  description = "Jenkins fully-qualified domain name"
  value       = aws_route53_record.jenkins.fqdn
}

output "ssh_command" {
  description = "SSH command template to reach the instance"
  value       = "ssh -i <path-to-private-key> ubuntu@${aws_eip.jenkins.public_ip}"
}

output "initial_password_command" {
  description = "Command to fetch Jenkins initial admin password"
  value       = "ssh -i <path-to-private-key> ubuntu@${aws_eip.jenkins.public_ip} sudo cat /var/lib/jenkins/secrets/initialAdminPassword"
}
