#!/usr/bin/env bash
set -euo pipefail

#############################################
# CONFIGURACIÓN DEL USUARIO
#############################################

REGION="us-west-2"
AZ1="us-west-2a"
AZ2="us-west-2b"

# CIDRs recomendados para escalabilidad
VPC_CIDR="10.0.0.0/16"

PUBLIC1_CIDR="10.0.0.0/20"
PUBLIC2_CIDR="10.0.16.0/20"

PRIVATE_SHARED1_CIDR="10.0.128.0/20"
PRIVATE_SHARED2_CIDR="10.0.144.0/20"

#############################################
# 1. CREAR VPC
#############################################

echo "🔵 Creando VPC..."
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block $VPC_CIDR \
  --region $REGION \
  --query 'Vpc.VpcId' \
  --output text)

echo "⏳ Esperando a que la VPC esté disponible..."
aws ec2 wait vpc-available --vpc-ids $VPC_ID --region $REGION
echo "   ✔️ VPC disponible"

# 🔧 Habilitar DNS — requerido para endpoints Interface (STS, ECR, EC2, Logs)
aws ec2 modify-vpc-attribute \
  --vpc-id $VPC_ID \
  --enable-dns-support "{\"Value\":true}" \
  --region $REGION

aws ec2 modify-vpc-attribute \
  --vpc-id $VPC_ID \
  --enable-dns-hostnames "{\"Value\":true}" \
  --region $REGION

aws ec2 create-tags \
  --resources $VPC_ID \
  --tags Key=Name,Value=shared-multi-eks-vpc

echo "   ✔️ VPC_ID = $VPC_ID"

#############################################
# 2. CREAR IGW
#############################################

echo "🔵 Creando Internet Gateway..."
IGW_ID=$(aws ec2 create-internet-gateway \
  --region $REGION \
  --query 'InternetGateway.InternetGatewayId' \
  --output text)

aws ec2 attach-internet-gateway \
  --internet-gateway-id $IGW_ID \
  --vpc-id $VPC_ID \
  --region $REGION

echo "   ✔️ IGW_ID = $IGW_ID"

#############################################
# 3. SUBNETS PÚBLICAS
#############################################

echo "🔵 Creando Subnets públicas..."

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

echo "   ✔️ PUB1_ID = $PUB1_ID"
echo "   ✔️ PUB2_ID = $PUB2_ID"

#############################################
# 4. SUBNETS PRIVADAS (COMPARTIDAS)
#############################################

echo "🔵 Creando Subnets privadas compartidas..."

PVT_SHARED1_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block $PRIVATE_SHARED1_CIDR \
  --availability-zone $AZ1 \
  --region $REGION \
  --query 'Subnet.SubnetId' --output text)

PVT_SHARED2_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block $PRIVATE_SHARED2_CIDR \
  --availability-zone $AZ2 \
  --region $REGION \
  --query 'Subnet.SubnetId' --output text)

echo "   ✔️ PVT_SHARED1_ID = $PVT_SHARED1_ID"
echo "   ✔️ PVT_SHARED2_ID = $PVT_SHARED2_ID"

#############################################
# 5. ROUTE TABLE PÚBLICA + RUTA 0.0.0.0/0
#############################################

echo "🔵 Creando Route Table pública..."

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

echo "   ✔️ RTB_PUBLIC = $RTB_PUBLIC"

#############################################
# 6. NAT GATEWAY
#############################################

echo "🔵 Creando Elastic IP para NAT Gateway..."
EIP_ALLOC=$(aws ec2 allocate-address \
  --domain vpc \
  --region $REGION \
  --query 'AllocationId' --output text)

echo "🔵 Creando NAT Gateway..."
NAT_GW=$(aws ec2 create-nat-gateway \
  --subnet-id $PUB1_ID \
  --allocation-id $EIP_ALLOC \
  --region $REGION \
  --query 'NatGateway.NatGatewayId' --output text)

echo "   ⏳ Esperando a que NAT Gateway esté disponible..."
aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_GW --region $REGION

echo "   ✔️ NAT_GW = $NAT_GW"

#############################################
# 7. ROUTE TABLE PRIVADA
#############################################

echo "🔵 Creando Route Table privada..."

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

echo "   ✔️ RTB_PRIVATE = $RTB_PRIVATE"


S3_ENDPOINT_ID=$(aws ec2 create-vpc-endpoint \
  --vpc-id $VPC_ID \
  --service-name com.amazonaws.$REGION.s3 \
  --vpc-endpoint-type Gateway \
  --route-table-ids $RTB_PRIVATE \
  --region $REGION \
  --query 'VpcEndpoint.VpcEndpointId' \
  --output text)

SG_VPCE=$(aws ec2 create-security-group \
  --group-name shared-vpce-sg \
  --description "SG for VPC endpoints" \
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


echo "🔵 Creando Instance Connect Endpoint..."

ICE_ID=$(aws ec2 create-instance-connect-endpoint \
  --subnet-id $PVT_SHARED1_ID \
  --security-group-ids $SG_VPCE \
  --region $REGION \
  --query 'InstanceConnectEndpoint.InstanceConnectEndpointId' \
  --output text)

echo "   ✔️ Instance Connect Endpoint creado: $ICE_ID"

aws ec2 authorize-security-group-ingress \
  --group-id $SG_VPCE \
  --protocol tcp \
  --port 22 \
  --cidr $VPC_CIDR \
  --region $REGION


#############################################
# 8. RESULTADOS
#############################################

echo ""
echo "====================================================="
echo " 🎉 VPC CREADA EXITOSAMENTE "
echo "====================================================="
echo "VPC_ID:              $VPC_ID"
echo "IGW_ID:              $IGW_ID"
echo "PUBLIC SUBNETS:      $PUB1_ID, $PUB2_ID"
echo "PRIVATE SUBNETS:     $PVT_SHARED1_ID, $PVT_SHARED2_ID"
echo "ROUTE TABLE PUBLIC:  $RTB_PUBLIC"
echo "ROUTE TABLE PRIVATE: $RTB_PRIVATE"
echo "NAT GATEWAY:         $NAT_GW"
echo "====================================================="
echo "Puedes usar esta VPC directamente en eksctl:"
echo "vpc.id: \"$VPC_ID\""
echo "====================================================="




echo "🔵 Creando Security Group para la EC2 pública..."

SG_EC2=$(aws ec2 create-security-group \
  --group-name public-ec2-sg \
  --description "Security Group for Public EC2 Access" \
  --vpc-id $VPC_ID \
  --region $REGION \
  --query 'GroupId' \
  --output text)

echo "   ✔️ SG_EC2 = $SG_EC2"

MY_IP=$(curl -s ifconfig.me)

#TODO: open all protocols and ports just for demo purposes, change later
aws ec2 authorize-security-group-ingress \ 
  --group-id $SG_EC2 \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0 \
  --region $REGION

USER_DATA=$(cat <<EOF
#!/bin/bash
#TODO: implement user-data script from external file
EOF)

echo "🔵 Obteniendo AMI de Ubuntu Server 24.04 LTS..."

AMI_ID=$(aws ssm get-parameter \
    --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
    --region $REGION \
    --query "Parameter.Value" \
    --output text)

echo "   ✔️ AMI_ID = $AMI_ID"


echo "🔵 Creando instancia EC2 (Ubuntu 24.04) en subnet pública..."

EC2_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type t3.2xlarge \
  --subnet-id $PUB1_ID \
  --security-group-ids $SG_EC2 \
  --associate-public-ip-address \
  --user-data "$USER_DATA" \
  --region $REGION \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=public-ubuntu-24}]" \
  --query 'Instances[0].InstanceId' \
  --output text)

echo "   ✔️ EC2 creada con ID: $EC2_ID"

EC2_PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids $EC2_ID \
  --region $REGION \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text)

echo "   🌐 EC2 Public IP: $EC2_PUBLIC_IP"
