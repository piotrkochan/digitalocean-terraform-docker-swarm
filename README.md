# Docker Swarm Cluster on DigitalOcean with Terraform

This project uses Terraform to set up a Docker Swarm cluster on DigitalOcean with rclone plugin.

## Key eatures

- Setup VMs for Docker Swarm cluster
- Creates a DigitalOcean Spaces bucket for data storage
- Installs and configures rclone for integration with DigitalOcean Spaces
- Configures a DigitalOcean firewall to Access Swarm (I'm using Portainer in Docker Dekstop)

## Setup

1. Create `local.tfvars` file based on `local.tfvars.example`
2. Setup ssh key
   ```
   ssh-keygen -t ed25519 -f ~/.ssh/do
   ```
3. Apply changes
   ```
   terraform apply -var-file="local.tfvars"
   ```

## Usage

1. SSH into any of the Droplets using the IP addresses output by Terraform:
   ```
   ssh -i ~/.ssh/do root@<droplet_ip>
   ```

2. Initialize the Docker Swarm on one of the nodes:
   ```
   docker swarm init
   ```

3. Join the other nodes to the swarm using the command provided by the init process.
4. You can now deploy services to your Docker Swarm cluster.

## Volume usage

Example docker-compose.yaml

```
version: '3.8'

services:
  wordpress:
    image: wordpress:latest
    volumes:
      - wp_content:/var/www/html/wp-content

volumes:
  wp_content:
    driver: rclone
    driver_opts:
      remote: 'spaces:wordpress-data-uhbp8u8h/wp-content'
      allow_other: 'true'
      vfs_cache_mode: full
      poll_interval: 0
```

https://github.com/piotrkochan/portainer-gitops/blob/master/stack-1/docker-compose.yaml

## Security Notes

- The firewall is configured to allow inbound traffic on ports 22 (SSH), 80 (HTTP), and 443 (HTTPS) from any source.
- Additional ports (8080, 3000, 2375) are only accessible from the IP specified in the `my_ip` variable.
- Inter-node communication for Docker Swarm is allowed on the necessary ports.
