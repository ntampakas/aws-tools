#!/bin/bash
set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 {instance-id}"
    exit 1
fi

_instance_state () {
    instance_state=$(aws ec2 describe-instances --profile $PROFILE --instance-id $INSTANCE_ID --query "Reservations[].Instances[].State.[Name]" --output text)
}

PROFILE="default"
VPC_ID="vpc-00334ffe7c9e3a2b2"
INSTANCE_ID=$1
AZs=(eu-central-1a eu-central-1b eu-central-1c)
COUNT=0

DESCRIBE_INSTANCE=$(aws ec2 describe-instances --profile $PROFILE --filters "Name=network-interface.vpc-id,Values=[$VPC_ID]" --instance-ids $INSTANCE_ID)
INSTANCE_AZ=$(echo $DESCRIBE_INSTANCE | jq -r .Reservations[].Instances[].Placement.AvailabilityZone)
INSTANCE_TYPE=$(echo $DESCRIBE_INSTANCE | jq -r .Reservations[].Instances[].InstanceType)
INSTANCE_KEYNAME=$(echo $DESCRIBE_INSTANCE | jq -r .Reservations[].Instances[].KeyName)
INSTANCE_SG=$(echo $DESCRIBE_INSTANCE | jq -r .Reservations[].Instances[].SecurityGroups[].GroupId)
INSTANCE_TAG=$(echo $DESCRIBE_INSTANCE | jq -r .Reservations[].Instances[].Tags[].Value)
VOLUME_ID=$(echo $DESCRIBE_INSTANCE | jq -r .Reservations[].Instances[].BlockDeviceMappings[].Ebs.VolumeId)
VOLUME_DEVICENAME=$(echo $DESCRIBE_INSTANCE | jq -r .Reservations[].Instances[].BlockDeviceMappings[].DeviceName)
VOLUME_SIZE=$(aws ec2 describe-volumes --profile $PROFILE --volume-ids $VOLUME_ID | jq -r .Volumes[].Size)

echo "$INSTANCE_ID is currently running in $INSTANCE_AZ"
echo "Move instance to Availability Zone:"
for AZ in ${AZs[@]/$INSTANCE_AZ};
do
    ((COUNT+=1))
    echo " $COUNT. $AZ"
done

read -p "Enter the name of the zone: " ZONE_SELECTED
[ "$ZONE_SELECTED" != "$INSTANCE_AZ" ] || exit 1

case $ZONE_SELECTED in
    "eu-central-1a")
        SUBNET="subnet-0e1c657227636974b"
        ;;
    "eu-central-1b")
        SUBNET="subnet-0ae9ef89e4b62d115"
        ;;
    "eu-central-1c")
        SUBNET="subnet-01349b070c0af0242"
        ;;
    *)
        echo "Please enter the name of the zone"
        exit 1
        ;;
esac

_instance_state
if [ "$instance_state" != "stopped" ]; then
    echo "Stopping instance..."
    aws ec2 stop-instances --profile $PROFILE --instance-ids $INSTANCE_ID --output table
    sleep 90
fi

# Check if AMI exists and (re)create 
echo "Creating AMI..."
AMI_EXISTS=$(aws ec2 describe-images --profile $PROFILE --filters "Name=tag:Name,Values=$INSTANCE_ID" --query "Images[].ImageId" --output text)
if [ ! -z $AMI_EXISTS ]; then
    SNAPSHOT_ID=$(aws ec2 describe-images --profile $PROFILE --filters "Name=tag:Name,Values=$INSTANCE_ID" --query "Images[].BlockDeviceMappings[].Ebs[].SnapshotId" --output text)
    aws ec2 deregister-image --profile $PROFILE --image-id $AMI_EXISTS
    aws ec2 delete-snapshot --profile $PROFILE --snapshot-id $SNAPSHOT_ID
fi

AMI_ID=$(aws ec2 create-image --profile $PROFILE --instance-id $INSTANCE_ID --name "$INSTANCE_ID" --description "$INSTANCE_ID" --tag-specifications "ResourceType=image,Tags=[{Key=Name,Value=$INSTANCE_ID}]" --output text)

echo "AMI status pending..."
aws ec2 wait image-exists --profile $PROFILE --filters "Name=tag:Name,Values=$INSTANCE_ID" "Name=state,Values=available"

# Migrate instance
echo "Migrating instance to $ZONE_SELECTED zone..."
INSTANCE_ID=$(aws ec2 run-instances --profile $PROFILE --image-id $AMI_ID --count 1 --instance-type $INSTANCE_TYPE --key-name $INSTANCE_KEYNAME --security-group-ids $INSTANCE_SG --subnet-id $SUBNET --block-device-mapping DeviceName=$VOLUME_DEVICENAME,Ebs={VolumeSize=$VOLUME_SIZE} --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_TAG}]" --query "Instances[0].InstanceId" --output text)

aws ec2 describe-instances --profile $PROFILE --filters "Name=network-interface.vpc-id,Values=[$VPC_ID]" --instance-ids $INSTANCE_ID --query "Reservations[].Instances[].[{InstanceID: InstanceId, ipv4: PrivateIpAddress}]" --output table
