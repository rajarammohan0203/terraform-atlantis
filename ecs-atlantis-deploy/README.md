# Atlantis AWS ECS Deployment

This directory contains the Terraform infrastructure code to deploy a highly available, production-ready Atlantis environment on AWS ECS using EC2 instances.

## System Architecture & Workflow

### 1. High-Level Architecture

This diagram outlines how the AWS infrastructure components connect to securely host Atlantis.

```mermaid
flowchart TB
    %% External Entities
    Developer((Developer))
    GitHub[GitHub Repository]

    %% AWS Cloud
    subgraph AWS_Cloud [AWS Cloud]
        direction TB

        IGW[Internet Gateway]

        subgraph VPC [VPC: 10.0.0.0/16]
            direction TB
            subgraph Public_Subnets [Public Subnets AZ1 & AZ2]
                ALB{{Application Load Balancer \n port: 80}}

                subgraph ASG [Auto Scaling Group: Min/Max 1]
                    EC2_Instance(Amazon Linux 2023 EC2 Instance\nSecurity Group: EC2 SG)

                    subgraph ECS_Task [ECS Task: Atlantis]
                        direction TB
                        Atlantis_Container[Atlantis Docker Container\nPort: 4141]
                    end

                    EBS_Volume[(Data EBS Volume\n/mnt/atlantis_data)]
                end
            end
        end

        %% AWS Services outside VPC
        SSM_Params[(SSM Parameter Store\nGitHub Tokens)]
        S3_State[(S3 Bucket\nTerraform State)]
        IAM_Roles{IAM Roles\nTask & Execution}
        CloudWatch[CloudWatch Logs\n/ecs/atlantis]
        Target_Resources((Target AWS Resources\ne.g., new S3 buckets))
    end

    %% Connections
    Developer -- Pushes Code & PR --> GitHub
    GitHub -- Webhook Payload --> IGW
    IGW --> ALB
    ALB -- Routes to dynamic port --> EC2_Instance
    EC2_Instance -- Runs --> ECS_Task
    Atlantis_Container -- Bind Mounts --> EBS_Volume
    Atlantis_Container -- Assumes --> IAM_Roles
    Atlantis_Container -- Reads Secrets --> SSM_Params
    Atlantis_Container -- Writes Logs --> CloudWatch
    Atlantis_Container -- terraform apply --> S3_State
    Atlantis_Container -- Provisions --> Target_Resources

    %% Styling
    classDef aws fill:#FF9900,stroke:#232F3E,stroke-width:2px,color:black
    classDef vpc fill:#f4f4f4,stroke:#00a4a6,stroke-width:2px,stroke-dasharray: 5 5
    classDef container fill:#0db7ed,stroke:#000,stroke-width:2px,color:white
    classDef storage fill:#3F8624,stroke:#000,stroke-width:2px,color:white

    class VPC,Public_Subnets vpc
    class EC2_Instance,ALB,IGW aws
    class Atlantis_Container container
    class EBS_Volume,S3_State,SSM_Params storage
```

### 2. Step-by-Step Workflow

This sequence diagram breaks down the end-to-end request lifecycle when a developer interacts with the repository.

```mermaid
sequenceDiagram
    autonumber
    actor Developer
    participant GitHub
    participant ALB as Application Load Balancer
    participant Atlantis as ECS: Atlantis Container
    participant SSM as AWS Systems Manager
    participant AWS as AWS Infrastructure

    Developer->>GitHub: Push Code & Open Pull Request
    GitHub->>ALB: Trigger Webhook (/events)
    ALB->>Atlantis: Route Traffic to Container
    Atlantis->>SSM: Retrieve GitHub Token & Webhook Secret securely
    Atlantis->>AWS: Assume ECS Task Role & Execute `terraform plan`
    Atlantis-->>GitHub: Post Plan Results as PR Comment
    Developer->>GitHub: Review & Comment `atlantis apply`
    GitHub->>ALB: Trigger Webhook (Apply Command)
    ALB->>Atlantis: Route Traffic to Container
    Atlantis->>AWS: Execute `terraform apply`
    AWS-->>Atlantis: Resources Created & State Updated in S3
    Atlantis-->>GitHub: Post Apply Success message & Merge PR
```

### Architecture Highlights

- **ALB**: Publicly accessible Load Balancer (`http`).
- **ASG + EC2**: Auto Scaling Group managing Amazon Linux 2023 instances.
- **Persistent Storage**: A dedicated EBS volume dynamically formatted and mounted via EC2 User Data to persist PR logs/workspaces across container restarts.
- **SSM Parameters**: Secure storage for your GitHub Token and Webhook Secret (never stored in plaintext state).
- **Dynamic Port Mapping**: Handled automatically by ECS bridging with ALB target groups.

## Deployment Instructions

### 1. Initialize and Apply

Review `variables.tf` and provide the required variables during apply:

```bash
terraform init
terraform apply -var="github_user=rajarammohan0203" -var="github_repo_allowlist=github.com/rajarammohan0203/terraform-atlantis"
```

_(Note: It will output an `atlantis_url` at the end. Copy this!)_

### 2. Set the Secrets

For security, Terraform created dummy parameters in AWS Systems Manager (SSM) because committing secrets tracking in state is dangerous. You need to update them with the real values.
Run the following commands using the AWS CLI, replacing the `<...>` with your actual values:

```bash
aws ssm put-parameter --name "/atlantis/github_token" \
  --value "ghp_YOUR_ACTUAL_TOKEN" \
  --type "SecureString" --overwrite

aws ssm put-parameter --name "/atlantis/webhook_secret" \
  --value "YOUR_WEBHOOK_SECRET" \
  --type "SecureString" --overwrite
```

### 3. Restart the ECS Task

Because the task initially booted with dummy secrets, you must force ECS to cycle the container to inject the newly updated secrets:

```bash
aws ecs update-service --cluster atlantis-cluster \
  --service atlantis-service \
  --force-new-deployment \
  --region ap-south-1
```

### 4. Update GitHub Webhook

1. Go to your GitHub repository **Settings > Webhooks**.
2. Edit your existing webhook (or create a new one).
3. Change the **Payload URL** from your old Ngrok URL to the new ALB URL outputted from Terraform:
   `http://<YOUR_ALB_DNS_NAME>/events`
4. Ensure the Content type is `application/json` and the Secret matches what you put in SSM.
5. Save.

Your robust AWS deployment of Atlantis is now live!
