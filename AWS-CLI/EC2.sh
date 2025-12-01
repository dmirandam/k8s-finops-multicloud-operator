#!/bin/bash
aws ec2 run-instances \
  --image-id ami-00f46ccd1cbfb363ez \
  --instance-type t3.micro \
  --key-name mi-keypair \
  --security-group-ids sg-0123456789abcdef0 \
  --subnet-id subnet-0123456789abcdef0 \
  --user-data file://user-data.sh \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=DemoUserData}]'
