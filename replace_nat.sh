#!/bin/bash

set -e

######################################
#    AWS credential
######################################
export AWS_ACCESS_KEY_ID=$BOSH_AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$BOSH_AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION=us-east-1
######################################

nat_ami=ami-f619c29f

######################################
#   Nat box information
######################################
new_nat_instance_type=m3.xlarge
key_name=bosh
security_group=nats_demo
subnet_id=subnet-e5267ccd
cf_nat_name=cf_nat_box_xlarge
cf_private_ip=10.8.0.10
nat_elastic_ip=54.85.28.163
old_nat_instance_id=i-8b69f2a8
nat_zone=us-east-1b
######################################

# Launching nat_box instance for replacing
echo "launching backup nat_box instances"
echo "======================="
sg_id=`aws ec2 describe-security-groups --filters Name=group-name,Values=$security_group | jq -r .SecurityGroups[].GroupId`

nat_replace=`aws ec2 run-instances --image-id $nat_ami --count 1 --instance-type $new_nat_instance_type --key-name $key_name --security-group-ids $sg_id --subnet-id $subnet_id \
   --placement AvailabilityZone=$nat_zone --private-ip-address $cf_private_ip | jq -r .Instances[0].InstanceId`

echo "Waiting a while for the box spin up"
echo "======================="
sleep 40

aws ec2 --output text modify-instance-attribute --instance-id $nat_replace --no-source-dest-check
aws ec2 --output text create-tags --resources $nat_replace  --tags Key=Name,Value=$cf_nat_name

# Elastic IP Move
### Detach EIPs
echo "Get Elastic IP allocation_id"
echo "======================="
eipalloc_nat=`aws ec2 describe-addresses --public-ips $nat_elastic_ip | jq -r .Addresses[0].AllocationId`

### Attach EIPs to new nat box
echo "attaching Elastic IPs to new nat"
echo "======================="
aws ec2 associate-address --instance-id $nat_replace --allocation-id $eipalloc_nat --allow-reassociation

# Route tables Manuplating
echo "Get route table IDs"
echo "======================="
rts_nat=`aws ec2 describe-route-tables --filter Name=route.instance-id,Values=$old_nat_instance_id | jq -r .RouteTables[].RouteTableId`

for rt in $rts_nat
do
  echo "replace route $rt"
  echo "======================="
  aws ec2 replace-route --route-table-id $rt --instance-id $nat_replace --destination-cidr-block '0.0.0.0/0'
done

echo "Done"
