# Jenkins access from management EC2 (notes and fixes)

This doc summarizes the challenges we hit when securing SSH access to the Jenkins EC2 from a management EC2 without using an Elastic IP on the management host, plus the exact commands to run and sample outputs.

## Challenges
- Management EC2 public IP changes on stop/start, breaking CIDR-based SSH rules.
- AWS CLI errors due to missing region (`You must specify a region`).
- Wrong security group IDs when adding SG-to-SG rules (`InvalidGroup.NotFound`).
- Limited IAM policy on the Jenkins instance role (cannot describe security groups).
- Avoiding long-lived admin keys on the Jenkins box where possible.

## Approach: SG-to-SG rule (no EIP on management host)
Instead of allowing a changing public IP, allow SSH from the management EC2’s security group to the Jenkins EC2’s security group.

### Commands (run on the management EC2)
1) Set region:
```bash
export REGION=ap-south-1
```
2) Discover the management instance ID and SG:
```bash
MGMT_IID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
MGMT_SG=$(aws ec2 describe-instances --instance-ids "$MGMT_IID" \
  --query "Reservations[0].Instances[0].SecurityGroups[0].GroupId" \
  --output text --region "$REGION")
```
3) Discover the Jenkins SG:
```bash
JENKINS_SG=$(aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=*jenkins*sg*" "Name=group-name,Values=*jenkins*sg*" \
  --query "SecurityGroups[0].GroupId" --output text --region "$REGION")
```
4) Add ingress rule (SSH from management SG to Jenkins SG):
```bash
aws ec2 authorize-security-group-ingress \
  --group-id "$JENKINS_SG" \
  --protocol tcp --port 22 \
  --source-group "$MGMT_SG" \
  --region "$REGION"
```

### Validation (run on the management EC2)
- Describe the rule:
```bash
aws ec2 describe-security-group-rules \
  --security-group-ids "$JENKINS_SG" \
  --query "SecurityGroupRules[?FromPort==\`22\` && ToPort==\`22\`]" \
  --output table --region "$REGION"
```
- Sample authorize output:
```
{
  "Return": true,
  "SecurityGroupRules": [
    {
      "SecurityGroupRuleId": "sgr-086107850a9ff50e1",
      "GroupId": "sg-02efa2f2a3d2c8f3d",
      "ReferencedGroupInfo": { "GroupId": "sg-086e48134f7f5628f" },
      "IpProtocol": "tcp",
      "FromPort": 22,
      "ToPort": 22
    }
  ]
}
```
- SSH test (from management EC2):
```bash
ssh -i ~/.ssh/jenkins-key.pem ubuntu@jenkins.rdhcloudlab.com
ssh -i ~/.ssh/jenkins-key.pem ubuntu@13.200.26.100  # or jenkins.rdhcloudlab.com
```

## Other notes
- If you need AWS CLI on Jenkins with minimal perms, prefer extending the instance role via Terraform (add `ec2:DescribeSecurityGroups` if required) rather than dropping admin keys on the box.
- If you must place static keys on Jenkins, write them to `/var/lib/jenkins/.aws/{credentials,config}`, set ownership to `jenkins:jenkins`, and `chmod 600` the files. Avoid admin policies; use scoped access.
