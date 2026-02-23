# Atlantis Local Testing: End-to-End Setup Guide (From Scratch)

This comprehensive guide details exactly how to integrate **Atlantis** into your GitHub repository for Terraform Pull Request automation, running the server locally on your Mac via Docker, and executing a test infrastructure deployment to an AWS S3 bucket.

---

## 🏗 System Architecture Overview

This section visually maps the architecture and workflow of running Atlantis locally using Ngrok, bridging your local AWS keys with GitHub via Docker.

```mermaid
sequenceDiagram
    autonumber
    actor Developer
    participant GitHub
    participant Ngrok
    participant Atlantis (Docker)
    participant AWS

    Developer->>GitHub: Push Code & Open Pull Request
    GitHub->>Ngrok: Send Webhook Event (Public URL)
    Ngrok->>Atlantis (Docker): Forward traffic to localhost:4141
    Atlantis (Docker)->>AWS: Authenticate using ~/.aws/credentials
    Atlantis (Docker)->>AWS: Execute `terraform plan`
    Atlantis (Docker)-->>GitHub: Post Plan Results as PR Comment
    Developer->>GitHub: Review & Comment `atlantis apply`
    GitHub->>Ngrok: Send Webhook Event (Apply Command)
    Ngrok->>Atlantis (Docker): Forward traffic to localhost:4141
    Atlantis (Docker)->>AWS: Execute `terraform apply`
    AWS-->>Atlantis (Docker): Resource Created & State Updated
    Atlantis (Docker)-->>GitHub: Post Apply Success & Merge PR
```

When you follow this guide, you will execute this exact workflow:

1. **You** open a Pull Request containing Terraform code on GitHub.
2. **GitHub** sends a Webhook event over the public internet.
3. **Ngrok** intercepts that public webhook and securely tunnels it into your local Mac running on port `4141`.
4. **Docker** routes that port into the isolated Atlantis container.
5. **Atlantis** executes `terraform plan` using your mapped local AWS credentials.
6. **Atlantis** comments the plan output back onto the GitHub PR directly.
7. **You** review the plan and comment `atlantis apply`.
8. **Atlantis** automatically provisions the S3 bucket in AWS and updates the remote state file.

---

## 🛠 Prerequisites

Before starting, ensure you have the following installed on your Mac:

1. **Docker Desktop**: Running and active.
2. **Ngrok**: Installed via Homebrew (`brew install ngrok`).
3. **AWS CLI**: Installed and configured (`aws configure`).
4. **Git**: Installed.
5. **A GitHub Account**.

---

## Step 1: AWS IAM User & Backend Setup

Atlantis needs permissions to create resources in your AWS account. It is highly recommended to create a dedicated IAM user for Atlantis.

1. **Create an IAM User:** In your AWS Console, create a user named `atlantis`. Give it programmatic access (Access Key / Secret Key).
2. **Attach Policies:** For this demo, attach `AmazonS3FullAccess` (or AdministratorAccess if this is a secure sandbox).
3. **Configure Local Profile:** Open your Mac terminal and edit your credentials file:
   ```bash
   nano ~/.aws/credentials
   ```
   Add a specific `[atlantis]` block with the keys you just generated:
   ```ini
   [atlantis]
   aws_access_key_id = AKIAXXXXXX...
   aws_secret_access_key = XXXXXX...
   ```
4. **Create a State Bucket:** In your AWS Console, manually create an S3 bucket to hold your Terraform state (e.g., `rajaram-terraform-state`). Enable versioning on this bucket.

---

## Step 2: GitHub Authentication (Tokens & Webhooks)

Atlantis needs to authenticate to GitHub to read your code and post comments. GitHub needs a webhook to talk to Atlantis.

### 2.1 Create a Personal Access Token (PAT)

1. Go to GitHub -> Settings -> Developer Settings -> Personal Access Tokens -> Tokens (classic).
2. Click **Generate new token (classic)**.
3. Name it "Atlantis Local".
4. Check the `repo` scope (Full control of private repositories).
5. Generate and **COPY** the token (`ghp_...`).

### 2.2 Generate a Webhook Secret

This is a random string used to secure the webhook.

1. Run this in your Mac terminal:
   ```bash
   echo $RANDOM$RANDOM$RANDOM | md5
   ```
2. **COPY** the 32-character output.

---

## Step 3: Expose Localhost with Ngrok

Because your Atlantis container will run on your local laptop, GitHub cannot reach it directly. Ngrok creates a secure tunnel.

1. **Authenticate Ngrok:** (First time only) Go to [dashboard.ngrok.com](https://dashboard.ngrok.com/get-started/your-authtoken), copy your Authtoken command, and run it in your terminal:
   ```bash
   ngrok config add-authtoken <YOUR_TOKEN>
   ```
2. **Start the Tunnel:** Run this command to expose port 4141:
   ```bash
   ngrok http 4141
   ```
3. **COPY** the Forwarding HTTPS URL (e.g., `https://xxxx-xx-xx.ngrok-free.dev`).
4. **Leave this terminal running.**

---

## Step 4: Configure the GitHub Webhook

1. Go to your GitHub Repository -> Settings -> **Webhooks**.
2. Click **Add webhook**.
3. **Payload URL**: Paste your Ngrok URL and append `/events` to it. (e.g., `https://xxxx.ngrok-free.dev/events`).
4. **Content type**: Select `application/json`.
5. **Secret**: Paste the 32-character Webhook Secret from Step 2.2.
6. **Events**: Select "Let me select individual events" and check:
   - `Pull requests`
   - `Pull request reviews`
   - `Issue comments`
   - `Pushes`
7. Click **Add webhook**.

---

## Step 5: Run Atlantis Locally via Docker

Now we start the Atlantis server, feeding it all the tokens and URLs we just gathered.

1. Open a **New Terminal Tab**.
2. Export your environment variables carefully:
   _(Note: `REPO_ALLOWLIST` must use the `github.com/user/repo` format)._

```bash
export USERNAME="rajarammohan0203"
export TOKEN="ghp_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
export SECRET="XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
export URL="https://xxxx-xx-xx.ngrok-free.dev" # Exact Ngrok URL, NO /events
export REPO_ALLOWLIST="github.com/rajarammohan0203/terraform-atlantis"
```

3. **Run the Docker Container:**
   This command mounts your `~/.aws` folder into the container and tells Atlantis to use the `[atlantis]` profile you created in Step 1.

```bash
docker run -p 4141:4141 \
  -v ~/.aws:/home/atlantis/.aws:ro \
  -e AWS_PROFILE=atlantis \
  -e ATLANTIS_GH_USER=$USERNAME \
  -e ATLANTIS_GH_TOKEN=$TOKEN \
  -e ATLANTIS_GH_WEBHOOK_SECRET=$SECRET \
  -e ATLANTIS_REPO_ALLOWLIST=$REPO_ALLOWLIST \
  -e ATLANTIS_ATLANTIS_URL=$URL \
  runatlantis/atlantis server
```

If successful, it will say `Atlantis started - listening on port 4141`. **Leave this terminal running.**

---

## Step 6: Prepare the Infrastructure Code

Open a **New 3rd Terminal Tab** to work with Git. Ensure you have cloned your repository.

### 6.1 Create the Terraform File

Create a folder named `s3-demo` and add a `main.tf` file inside it. Note the `backend "s3"` block telling Terraform to store the state file safely in AWS instead of inside the fragile Docker container!

**`s3-demo/main.tf`**

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "rajaram-terraform-state" # The bucket you made in Step 1
    key    = "atlantis-demo/terraform.tfstate"
    region = "ap-south-1"
  }
}

provider "aws" {
  region = "ap-south-1"
}

resource "random_id" "bucket_suffix" {
  byte_length = 5
}

resource "aws_s3_bucket" "atlantis_demo" {
  bucket = "atlantis-demo-bucket-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "Atlantis Local Demo"
    Environment = "Dev"
  }
}
```

### 6.2 Create the Atlantis Config File

At the root of your repository, create an `atlantis.yaml` file so Atlantis knows which directories to scan.

**`atlantis.yaml`**

```yaml
version: 3
projects:
  - dir: s3-demo
    autoplan:
      when_modified: ["*.tf", "*.tfvars"]
      enabled: true
```

---

## Step 7: Push the Code and Trigger Atlantis!

We will use SSH to push the code securely to GitHub.

1. **Commit the code to a new branch:**

```bash
git checkout -b atlantis-test-s3
git add s3-demo/ atlantis.yaml
git commit -m "feat: Add S3 demo code for Atlantis"
git push origin atlantis-test-s3
```

2. **Open the PR:** Go to your GitHub repository in the browser and click **Compare & pull request**.
3. **Observe the Plan:** Within seconds, Atlantis will pick up the webhook, run `terraform plan`, and post a comment on your PR showing the exact resources it will create (1 random string, 1 S3 bucket).
4. **Execute the Apply:** In the PR comment box, type the following and click Comment:
   ```text
   atlantis apply -d s3-demo
   ```
5. **Verify:** Atlantis will run `terraform apply`, post a success message, and merge your PR. Go to your AWS S3 Console to see your brand new bucket!

---

## Troubleshooting

- **502 Bad Gateway from Ngrok**: Your Docker container isn't running or isn't bound to port 4141. Restart the `docker run` command.
- **"This repo is not allowlisted for Atlantis"**: You did not set the `ATLANTIS_REPO_ALLOWLIST` variable correctly before starting the Docker container. It must strictly match `github.com/username/repo`.
- **"No valid credential sources found"**: Atlantis cannot find your AWS credentials. Ensure your `AWS_PROFILE` matches a profile that actually exists inside your local `~/.aws/credentials` file, and that the volume mount `-v ~/.aws:/home/atlantis/.aws:ro` is correct.
