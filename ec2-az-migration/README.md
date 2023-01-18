# This is a tool that resolves the InsufficientInstanceCapacity error when starting/launching an EC2 instance.
## It creates an image from an Amazon EBS-backed instance and then migrates it to a new instance in a different availability zone.

### Usage:
```
# ./migrate_ec2.sh i-05f02cdc0f3c91xxx
Move instance to Availability Zone:
 1. eu-central-1a
 2. eu-central-1c
Enter the name of the zone: eu-central-1c
Creating AMI...
AMI status pending...
Migrating instance to eu-central-1c zone...
---------------------------------------
|          DescribeInstances          |
+----------------------+--------------+
|      InstanceID      |    ipv4      |
+----------------------+--------------+
|  i-0a7018d3e80bd9xxx |  10.xx.3.69  |
+----------------------+--------------+
```
