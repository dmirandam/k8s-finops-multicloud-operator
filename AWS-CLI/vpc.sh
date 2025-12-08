#!/usr/bin/env bash

set -euo pipefail

CSI="\033["
RESET="${CSI}0m"
BOLD="${CSI}1m"
DIM="${CSI}2m"
RED="${CSI}31m"
GREEN="${CSI}32m"
YELLOW="${CSI}33m"
BLUE="${CSI}34m"
MAGENTA="${CSI}35m"
CYAN="${CSI}36m"

timestamp() {
    date +"%Y-%m-%d %H:%M:%S"
}

header() {
    echo -e "${BOLD}${CYAN}\n=== $1 ===${RESET}"
}

info() {
    echo -e "${BLUE}[$(timestamp)][INFO]${RESET} $1"
}

step() {
    echo -e "${YELLOW}[$(timestamp)][STEP]${RESET} $1"
}

success() {
    echo -e "${GREEN}[$(timestamp)][OK]${RESET} $1"
}

warn() {
    echo -e "${MAGENTA}[$(timestamp)][WARN]${RESET} $1"
}

err() {
    echo -e "${RED}[$(timestamp)][ERROR]${RESET} $1" >&2
}

on_error() {
    local exit_code=$?
    local line_no=${1:-"?"}
    err "Command failed at line ${line_no} with exit code ${exit_code}."
    exit ${exit_code}
}

trap 'on_error $LINENO' ERR

run_step() {
    local msg="$1"
    shift
    step "${msg}"
    "$@"
    success "Completed: ${msg}"
}

finish() {
    echo -e "${BOLD}${GREEN}=== All steps completed successfully ===${RESET}"
}

header "User Configuration"

export AWS_PAGER=cat
REGION="us-west-2"
AZ1="us-west-2a"
AZ2="us-west-2b"

VPC_CIDR="10.0.0.0/16"
PUBLIC1_CIDR="10.0.0.0/20"
PUBLIC2_CIDR="10.0.16.0/20"
PRIVATE_SHARED1_CIDR="10.0.128.0/20"
PRIVATE_SHARED2_CIDR="10.0.144.0/20"


header "IAM Cleanup (Best Effort)"
info "Performing preliminary IAM cleanup if entities exist. Continuing even upon failure."

trap - ERR

set +e
aws iam remove-role-from-instance-profile --instance-profile-name ec2-admin-instance-profile --role-name ec2-admin-role
aws iam detach-role-policy --role-name ec2-admin-role --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
aws iam delete-role-policy --role-name ec2-admin-role --policy-name AdministratorAccess
aws iam delete-role --role-name ec2-admin-role
aws iam delete-instance-profile --instance-profile-name ec2-admin-instance-profile
set -euo pipefail

trap 'on_error $LINENO' ERR

header "VPC Creation"
step "Creating VPC..."
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block $VPC_CIDR \
  --region $REGION \
  --query 'Vpc.VpcId' \
  --output text)

step "Waiting for VPC to become available..."
aws ec2 wait vpc-available --vpc-ids $VPC_ID --region $REGION
success "VPC is now available."

step "Enabling required DNS attributes for VPC..."
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support "{\"Value\":true}" --region $REGION
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames "{\"Value\":true}" --region $REGION

aws ec2 create-tags --resources $VPC_ID --tags Key=Name,Value=kfo-multi-eks-vpc

success "VPC_ID = $VPC_ID"

header "Internet Gateway Creation"

step "Creating Internet Gateway..."
IGW_ID=$(aws ec2 create-internet-gateway \
  --region $REGION \
  --query 'InternetGateway.InternetGatewayId' \
  --output text)

aws ec2 attach-internet-gateway \
  --internet-gateway-id $IGW_ID \
  --vpc-id $VPC_ID \
  --region $REGION

success "IGW_ID = $IGW_ID"

header "Public Subnet Creation"

step "Creating public subnets..."
PUB1_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block $PUBLIC1_CIDR \
  --availability-zone $AZ1 \
  --region $REGION \
  --query 'Subnet.SubnetId' --output text)

PUB2_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block $PUBLIC2_CIDR \
  --availability-zone $AZ2 \
  --region $REGION \
  --query 'Subnet.SubnetId' --output text)

aws ec2 modify-subnet-attribute --subnet-id $PUB1_ID --map-public-ip-on-launch --region $REGION
aws ec2 modify-subnet-attribute --subnet-id $PUB2_ID --map-public-ip-on-launch --region $REGION

success "PUB1_ID = $PUB1_ID"
success "PUB2_ID = $PUB2_ID"

header "Private Shared Subnet Creation"

step "Creating private shared subnets..."
PVT_SHARED1_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block $PRIVATE_SHARED1_CIDR \
  --availability-zone $AZ1 \
  --region $REGION \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key="karpenter.sh/discovery",Value="kfo"}]' \
  --query 'Subnet.SubnetId' --output text)

PVT_SHARED2_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block $PRIVATE_SHARED2_CIDR \
  --availability-zone $AZ2 \
  --region $REGION \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key="karpenter.sh/discovery",Value="kfo"}]' \
  --query 'Subnet.SubnetId' --output text)

success "PVT_SHARED1_ID = $PVT_SHARED1_ID"
success "PVT_SHARED2_ID = $PVT_SHARED2_ID"

header "Public Route Table Configuration"

step "Creating public route table..."
RTB_PUBLIC=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --region $REGION \
  --query 'RouteTable.RouteTableId' --output text)

aws ec2 create-route \
  --route-table-id $RTB_PUBLIC \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id $IGW_ID \
  --region $REGION

aws ec2 associate-route-table --route-table-id $RTB_PUBLIC --subnet-id $PUB1_ID --region $REGION
aws ec2 associate-route-table --route-table-id $RTB_PUBLIC --subnet-id $PUB2_ID --region $REGION

success "RTB_PUBLIC = $RTB_PUBLIC"


header "NAT Gateway Provisioning"

step "Allocating Elastic IP for NAT Gateway..."
EIP_ALLOC=$(aws ec2 allocate-address \
  --domain vpc \
  --region $REGION \
  --query 'AllocationId' --output text)

step "Creating NAT Gateway..."
NAT_GW=$(aws ec2 create-nat-gateway \
  --subnet-id $PUB1_ID \
  --allocation-id $EIP_ALLOC \
  --region $REGION \
  --query 'NatGateway.NatGatewayId' --output text)

step "Waiting for NAT Gateway to become available..."
aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_GW --region $REGION

success "NAT_GW = $NAT_GW"

header "Private Route Table & VPC Endpoints"

step "Creating private route table..."
RTB_PRIVATE=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --region $REGION \
  --query 'RouteTable.RouteTableId' --output text)

aws ec2 create-route \
  --route-table-id $RTB_PRIVATE \
  --destination-cidr-block 0.0.0.0/0 \
  --nat-gateway-id $NAT_GW \
  --region $REGION

aws ec2 associate-route-table --route-table-id $RTB_PRIVATE --subnet-id $PVT_SHARED1_ID --region $REGION
aws ec2 associate-route-table --route-table-id $RTB_PRIVATE --subnet-id $PVT_SHARED2_ID --region $REGION

success "RTB_PRIVATE = $RTB_PRIVATE"


step "Creating S3 Gateway Endpoint..."
S3_ENDPOINT_ID=$(aws ec2 create-vpc-endpoint \
  --vpc-id $VPC_ID \
  --service-name com.amazonaws.$REGION.s3 \
  --vpc-endpoint-type Gateway \
  --route-table-ids $RTB_PRIVATE \
  --region $REGION \
  --query 'VpcEndpoint.VpcEndpointId' \
  --output text)

step "Creating shared security group for VPC Endpoints..."
SG_VPCE=$(aws ec2 create-security-group \
  --group-name shared-vpce-sg \
  --description "Security Group for VPC endpoints" \
  --vpc-id $VPC_ID \
  --region $REGION \
  --query 'GroupId' \
  --output text)

aws ec2 authorize-security-group-ingress \
  --group-id $SG_VPCE \
  --protocol tcp \
  --port 443 \
  --cidr $VPC_CIDR \
  --region $REGION

step "Creating Interface Endpoints (EC2, ECR, STS, Logs)..."
for SERVICE in ec2 ecr.api ecr.dkr sts logs; do
  aws ec2 create-vpc-endpoint \
    --vpc-id $VPC_ID \
    --service-name com.amazonaws.$REGION.$SERVICE \
    --vpc-endpoint-type Interface \
    --subnet-ids $PVT_SHARED1_ID $PVT_SHARED2_ID \
    --security-group-ids $SG_VPCE \
    --private-dns-enabled \
    --region $REGION
done


step "Creating Instance Connect Endpoint..."
ICE_ID=$(aws ec2 create-instance-connect-endpoint \
  --subnet-id $PVT_SHARED1_ID \
  --security-group-ids $SG_VPCE \
  --region $REGION \
  --query 'InstanceConnectEndpoint.InstanceConnectEndpointId' \
  --output text)

success "Instance Connect Endpoint created: $ICE_ID"

aws ec2 authorize-security-group-ingress \
  --group-id $SG_VPCE \
  --protocol tcp \
  --port 22 \
  --cidr $VPC_CIDR \
  --region $REGION


header " VPC Result Summary"

echo ""
echo "====================================================="
echo " VPC successfully created and configured"
echo "====================================================="
echo "VPC_ID:              $VPC_ID"
echo "IGW_ID:              $IGW_ID"
echo "PUBLIC SUBNETS:      $PUB1_ID, $PUB2_ID"
echo "PRIVATE SUBNETS:     $PVT_SHARED1_ID, $PVT_SHARED2_ID"
echo "ROUTE TABLE PUBLIC:  $RTB_PUBLIC"
echo "ROUTE TABLE PRIVATE: $RTB_PRIVATE"
echo "NAT GATEWAY:         $NAT_GW"
echo "====================================================="



header "Public EC2 Security Group"

step "Creating security group for public EC2 access..."
SG_EC2=$(aws ec2 create-security-group \
  --group-name public-ec2-sg \
  --description "Security Group for Public EC2 Access" \
  --vpc-id $VPC_ID \
  --region $REGION \
  --query 'GroupId' \
  --output text)

success "SG_EC2 = $SG_EC2"

#MY_IP=$(curl -s ifconfig.me)

aws ec2 authorize-security-group-ingress \
  --group-id $SG_EC2 \
  --protocol -1 \
  --cidr 0.0.0.0/0 \
  --region $REGION

header "IAM Role and Instance Profile"

step "Creating IAM role for EC2..."
aws iam create-role \
  --role-name ec2-admin-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": { "Service": "ec2.amazonaws.com" },
        "Action": "sts:AssumeRole"
      }
    ]
  }' \
  --region $REGION

aws iam attach-role-policy \
  --role-name ec2-admin-role \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess \
  --region $REGION

aws iam create-instance-profile \
  --instance-profile-name ec2-admin-instance-profile \
  --region $REGION

aws iam add-role-to-instance-profile \
  --instance-profile-name ec2-admin-instance-profile \
  --role-name ec2-admin-role \
  --region $REGION

sleep 60

step "Waiting for role to propagate within instance profile..."

for i in {1..10}; do
  ROLE_COUNT=$(aws iam get-instance-profile \
    --instance-profile-name ec2-admin-instance-profile \
    --query 'InstanceProfile.Roles | length(@)' \
    --output text)

  if [[ "$ROLE_COUNT" -gt 0 ]]; then
    success "Role properly attached to Instance Profile."
    break
  fi

  info "Role not yet attached. Attempt $i/10..."
  sleep 3
done

aws iam get-instance-profile \
  --instance-profile-name ec2-admin-instance-profile \
  --region $REGION

header "Fetch AMI"

step "Retrieving Ubuntu Server 24.04 LTS AMI..."
AMI_ID=$(aws ssm get-parameter \
    --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
    --region $REGION \
    --query "Parameter.Value" \
    --output text)

success "AMI_ID = $AMI_ID"

header "Private EC2 Instance"

step "Creating Security Group for private EC2..."
SG_EC2_PRIVATE=$(aws ec2 create-security-group \
  --group-name private-ec2-sg \
  --description "Security Group for Private EC2 Access via Instance Connect Endpoint" \
  --vpc-id $VPC_ID \
  --region $REGION \
  --query 'GroupId' \
  --output text)

success "SG_EC2_PRIVATE = $SG_EC2_PRIVATE"

aws ec2 authorize-security-group-ingress \
  --group-id $SG_EC2_PRIVATE \
  --ip-permissions "IpProtocol=tcp,FromPort=22,ToPort=22,UserIdGroupPairs=[{GroupId=$SG_VPCE}]" \
  --region $REGION

aws ec2 authorize-security-group-ingress \
  --group-id $SG_EC2_PRIVATE \
  --protocol -1 \
  --cidr $VPC_CIDR \
  --region $REGION

step "Launching private EC2 instance (Ubuntu 24.04)..."
EC2_PRIVATE_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type t3.2xlarge \
  --subnet-id $PVT_SHARED1_ID \
  --security-group-ids $SG_EC2_PRIVATE \
  --user-data file://user-data-karmada.sh \
  --iam-instance-profile Name=ec2-admin-instance-profile \
  --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":50,"VolumeType":"gp3","DeleteOnTermination":true}}]' \
  --region $REGION \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=Karmada-ControlPlane}]" \
  --query 'Instances[0].InstanceId' \
  --output text)

success "Private EC2 instance created: $EC2_PRIVATE_ID"

EC2_PRIVATE_IP=$(aws ec2 describe-instances \
  --instance-ids $EC2_PRIVATE_ID \
  --region $REGION \
  --query "Reservations[0].Instances[0].PrivateIpAddress" \
  --output text)

info "Private EC2 IP Address: $EC2_PRIVATE_IP"

header "Public EC2 Instance"

step "Launching public EC2 instance (Ubuntu 24.04)..."
EC2_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type t3.   xlarge \
  --subnet-id $PUB1_ID \
  --security-group-ids $SG_EC2 \
  --associate-public-ip-address \
  --user-data file://user-data-tekton.sh \
  --iam-instance-profile Name=ec2-admin-instance-profile \
  --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":50,"VolumeType":"gp3","DeleteOnTermination":true}}]' \
  --region $REGION \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=Tekton-pipelines}]" \
  --query 'Instances[0].InstanceId' \
  --output text)

success "Public EC2 instance created: $EC2_ID"

EC2_PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids $EC2_ID \
  --region $REGION \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text)

info "Public EC2 IP Address: $EC2_PUBLIC_IP"