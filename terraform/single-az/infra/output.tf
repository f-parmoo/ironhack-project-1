output "ansible_inventory" {
  value = <<-EOT
[frontend]
frontend-ec2 ansible_host=${aws_instance.frontend.public_dns}

[backend]
backend-ec2 ansible_host=${aws_instance.backend.private_ip}

[db]
db-ec2 ansible_host=${aws_instance.db.private_ip}

[private:children]
backend
db

[all:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=../../keys/voting-project-key.pem
ansible_python_interpreter=/usr/bin/python3

[private:vars]
ansible_ssh_common_args='-o ProxyJump=ubuntu@${aws_instance.frontend.public_dns}'
EOT
}