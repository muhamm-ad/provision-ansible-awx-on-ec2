# Simplify Ansible AWX Provisioning on AWS EC2

This repository aims to **simplify** the deployment of [Ansible AWX](https://github.com/ansible/awx) onto an **AWS EC2 instance**. It leverages **Terraform** to provision infrastructure and **shell scripts** to automate the installation of a minimal [K3s](https://k3s.io/) cluster and AWX via the [AWX Operator](https://github.com/ansible/awx-operator).

## Overview

- **Goal**: Quickly spin up a fully functional AWX server with minimal manual intervention.
- **Key Components**:
    1. **Terraform**: Provisions an Ubuntu EC2 instance, configures networking/security, and uploads necessary setup scripts.
    2. **User Data + Provisioners**: Automatically installs K3s, Kustomize, and the AWX Operator on the instance.
    3. **AWX Operator**: Deploys AWX into the local K3s cluster. An ingress is created for easy browser access at the public DNS name returned by `terraform output -raw public_dns` (use HTTPS after adding TLS).

Using this repository, you avoid most manual steps and can focus on managing your Ansible playbooks in AWX.

## Prerequisites

Before proceeding, ensure the following requirements are met:

- **Terraform**: Version 1.8 or later installed. [Download Terraform here](https://www.terraform.io/downloads.html).
- **AWS Account**: With credentials (access key and secret key) for a user having sufficient permissions for managing EC2 resources.
- Ensure the **default VPC** in your AWS account is available in the region you specify and dns resolution and dns hostnames are enabled in the VPC.

## Usage

### 1. AWS Credentials

- Create a **`terraform.tfvars`** file and set:
  ```hcl
  aws_region          = "us-west-2"
  aws_access_key      = "YOUR_ACCESS_KEY"
  aws_secret_key      = "YOUR_SECRET_KEY"
  aws_access_token    = "YOUR_SESSION_TOKEN" # optional
  awx_server_ec2_type = "t2.xlarge" # optional
  ```

  > **Note**: By default, this uses `t2.xlarge` because AWX’s minimum recommended requirements are 4 CPUs and 8 GB of RAM. Keep in mind that this instance type may incur higher costs depending on your region and usage duration.

- Alternatively, export environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, etc.) or store secrets securely using a secrets manager.

### 2. Deploy with Terraform

```bash
# Initialize
terraform init

# Plan (optional) Review the changes to be applied.
terraform plan

# Apply
terraform apply
```

Type **`yes`** when prompted. Terraform will:
  - Launch the EC2 instance.
  - Upload and run the AWX setup scripts.
  - Start a systemd service that triggers the AWX deployment.

### 3. Verify AWX

- **Terraform Outputs**  
  After completion, Terraform displays:
    - `ec2_instance_id`
    - `public_ip`
    - `public_dns`
    - `aws_region`
    - `private_key_pem`

- **SSH**
  ```bash
  ssh -i <(terraform output -raw private_key_pem) ubuntu@$(terraform output -raw public_ip)
  ```
    - This allows you to check logs, pods, etc. within the instance.
    - After deployment, you should wait about 5 minutes for the AWX Operator to finish deploying the AWX server. To check the logs of the AWX Operator:
      ```bash
      kubectl logs -f deployments/awx-operator-controller-manager -c awx-manager -n awx
      ```
    - Refer to the [AWX Operator documentation](https://ansible.readthedocs.io/projects/awx-operator/en/latest/installation/basic-install.html) for more details.

- **AWX Access**
    - The AWX Operator creates an ingress route at your instance’s public DNS name.
    - To retrieve the **AWX admin password** (username: `admin` by default):
      ```bash
      kubectl get secret awx-admin-password -n awx -o jsonpath="{.data.password}" | base64 --decode
      ```
    - Visit `http://<public-hostname>` (or `https://<public-hostname>` if you add TLS) to log in.

## Cleaning Up

To remove all AWS resources:

```bash
terraform destroy
```

This tears down the EC2 instance, security group, and key pair. Any data stored on the instance (including AWX data) will be lost.

## Starting and Stopping the AWX Server

Install the [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) and configure it with the necessary permissions to start/stop your EC2 instance.

- **Start the AWX server**:
  ```bash
  aws ec2 start-instances \
    --region "$(terraform output -raw aws_region)" \
    --instance-ids "$(terraform output -raw ec2_instance_id)"
  ```
- **Stop the AWX server**:
  ```bash
  aws ec2 stop-instances \
    --region "$(terraform output -raw aws_region)" \
    --instance-ids "$(terraform output -raw ec2_instance_id)"
  ```
- **Describe the instance** (e.g., to get its public IP or status):
  ```bash
  aws ec2 describe-instances \
    --region "$(terraform output -raw aws_region)" \
    --instance-ids "$(terraform output -raw ec2_instance_id)"
  ```
  You can filter the output to only retrieve specific details like the public IP.

## Next Steps

- **TLS**: Integrate [Let’s Encrypt](https://letsencrypt.org/) or [cert-manager](https://cert-manager.io/) for a production-ready HTTPS setup.
- **Persistent Storage**: Use an EBS-backed StorageClass or another volume strategy for AWX data.

## LICENSE

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
