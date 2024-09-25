# Configure the DigitalOcean Provider
terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

# Set the variable for your DigitalOcean API token
variable "do_token" {}

# Spaces token
variable "storage_access_id" {}
variable "storage_secret_key" {}

# Configure the DigitalOcean Provider
provider "digitalocean" {
  token             = var.do_token
  spaces_access_id  = var.storage_access_id
  spaces_secret_key = var.storage_secret_key
}

# Create a new SSH key
resource "digitalocean_ssh_key" "kafka_ssh_key" {
  name       = "Kafka SSH Key"
  public_key = file("~/.ssh/do.pub")
}

# Create a new VPC
resource "digitalocean_vpc" "docker_swarm_vpc" {
  name     = "docker-swarm-vpc"
  region   = "fra1"
  ip_range = "10.10.12.0/24"
}

resource "digitalocean_tag" "docker_swarm" {
  name = "docker-swarm"
}

resource "local_file" "rclone_config" {
  content  = <<-EOT
    [spaces]
    type = s3
    provider = DigitalOcean
    env_auth = false
    access_key_id = ${var.storage_access_id}
    secret_access_key = ${var.storage_secret_key}
    endpoint = fra1.digitaloceanspaces.com
    acl = private
  EOT
  filename = "${path.module}/rclone.conf"
}

resource "digitalocean_droplet" "docker_swarm_node" {
  count    = 3
  image    = "ubuntu-24-04-x64"
  name     = "docker-node-${count.index + 1}"
  region   = "fra1"
  size     = "s-2vcpu-4gb"
  vpc_uuid = digitalocean_vpc.docker_swarm_vpc.id
  ssh_keys = [digitalocean_ssh_key.kafka_ssh_key.fingerprint]
  tags     = [digitalocean_tag.docker_swarm.id]

  connection {
    host        = self.ipv4_address
    user        = "root"
    type        = "ssh"
    private_key = file("~/.ssh/do")
    timeout     = "2m"
  }

  provisioner "file" {
    source      = local_file.rclone_config.filename
    destination = "/tmp/rclone.conf"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt install -y docker.io",
      "sudo mkdir -p /etc/systemd/system/docker.service.d",
      "echo '[Service]' | sudo tee /etc/systemd/system/docker.service.d/override.conf",
      "echo 'ExecStart=' | sudo tee -a /etc/systemd/system/docker.service.d/override.conf",
      "echo 'ExecStart=/usr/bin/dockerd -H fd:// -H tcp://0.0.0.0:2375' | sudo tee -a /etc/systemd/system/docker.service.d/override.conf",
      "sudo systemctl daemon-reload",
      "sudo systemctl restart docker",

      "sudo apt-get -y install fuse fuse3",
      "sudo mkdir -p /var/lib/docker-plugins/rclone/config",
      "sudo mkdir -p /var/lib/docker-plugins/rclone/cache",
      "sudo mkdir -p /var/lib/docker-plugins/rclone/config",
      "sudo mv /tmp/rclone.conf /var/lib/docker-plugins/rclone/config/rclone.conf",
      "sudo docker plugin install rclone/docker-volume-rclone:amd64 args='-v' --alias rclone --grant-all-permissions"
    ]
  }
}

resource "digitalocean_firewall" "docker_swarm_firewall" {
  name = "docker-swarm-firewall"

  droplet_ids = digitalocean_droplet.docker_swarm_node[*].id

  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "80"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "8080"
    source_addresses = ["${var.my_ip}/32"]
  }

  # obsidian
  inbound_rule {
    protocol         = "tcp"
    port_range       = "3000"
    source_addresses = ["${var.my_ip}/32"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "2375"
    source_addresses = ["${var.my_ip}/32"]
  }

  inbound_rule {
    protocol    = "tcp"
    port_range  = "2377"
    source_tags = ["docker-swarm"]
  }

  # Communication among nodes
  inbound_rule {
    protocol    = "tcp"
    port_range  = "7946"
    source_tags = ["docker-swarm"]
  }

  inbound_rule {
    protocol    = "udp"
    port_range  = "7946"
    source_tags = ["docker-swarm"]
  }

  # Overlay network traffic
  inbound_rule {
    protocol    = "udp"
    port_range  = "4789"
    source_tags = ["docker-swarm"]
  }

  # Allow all outbound traffic
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

resource "digitalocean_spaces_bucket" "wordpress_data" {
  name   = "wordpress-data-${random_string.random.result}"
  region = "fra1"
  acl    = "private"
}

# Generate a random string for unique bucket naming
resource "random_string" "random" {
  length  = 8
  special = false
  upper   = false
}

variable "my_ip" {
  description = "Your public IP address"
  type        = string
}

# Output the IP addresses
output "docker_swarm_node_ips" {
  value = digitalocean_droplet.docker_swarm_node[*].ipv4_address
}