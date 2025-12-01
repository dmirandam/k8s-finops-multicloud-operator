#!/bin/bash
yum update -y
echo "Hola desde user-data" > /home/ec2-user/bienvenida.txt
