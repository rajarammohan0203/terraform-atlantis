resource "aws_ecs_cluster" "atlantis" {
  name = "atlantis-cluster"
}

# Get the latest Amazon Linux 2023 ECS Optimized AMI
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}

resource "aws_launch_template" "ecs_ec2" {
  name_prefix   = "atlantis-ecs-template-"
  image_id      = data.aws_ssm_parameter.ecs_ami.value
  instance_type = "t3.small" # Use Nitro instance type

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance_profile.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.ecs_instances.id]
  }

  # User data to register instance to ECS cluster and dynamically format/mount the extra EBS volume
  user_data = base64encode(<<EOF
#!/bin/bash
# Join the ECS cluster
echo "ECS_CLUSTER=${aws_ecs_cluster.atlantis.name}" >> /etc/ecs/ecs.config

sleep 15 # Wait for secondary EBS volume attachment

# Dynamically find the secondary volume (ignore the root nvme0n1)
VOLUME_DEV=$(lsblk -o NAME,TYPE | awk '$2=="disk"' | grep -v 'nvme0n1' | awk '{print "/dev/"$1}')

if [ ! -z "$VOLUME_DEV" ]; then
  # Check if it has a filesystem. If not, format it.
  if ! blkid $VOLUME_DEV; then
    echo "Formatting $VOLUME_DEV..."
    mkfs -t ext4 $VOLUME_DEV
  fi

  # Create mount point and mount
  mkdir -p /mnt/atlantis_data
  mount $VOLUME_DEV /mnt/atlantis_data
  
  # Ensure it mounts automatically on reboot
  echo "$VOLUME_DEV /mnt/atlantis_data ext4 defaults,nofail 0 2" >> /etc/fstab

  # Give Docker permissions to the directory (Atlantis runs as user 'atlantis' with UID 100)
  chown -R 100:100 /mnt/atlantis_data
fi
EOF
  )

  # Adding an extra EBS volume for Atlantis data persistence
  block_device_mappings {
    device_name = "/dev/sdf"
    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      delete_on_termination = false # KEEP the data if the instance terminates!
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "ecs_asg" {
  name                = "atlantis-ecs-asg"
  vpc_zone_identifier = module.vpc.public_subnets
  desired_capacity    = 1
  max_size            = 1
  min_size            = 1

  launch_template {
    id      = aws_launch_template.ecs_ec2.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "atlantis-ecs-instance"
    propagate_at_launch = true
  }

  protect_from_scale_in = false
  force_delete          = true
}

resource "aws_ecs_capacity_provider" "ec2" {
  name = "atlantis-ec2-provider"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs_asg.arn
    managed_termination_protection = "DISABLED"

    managed_scaling {
      maximum_scaling_step_size = 1
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = 100
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.atlantis.name
  capacity_providers = [aws_ecs_capacity_provider.ec2.name]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = aws_ecs_capacity_provider.ec2.name
  }
}
