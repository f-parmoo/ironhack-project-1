import json
import os
import boto3
import paramiko

ec2 = boto3.client("ec2")
autoscaling = boto3.client("autoscaling")
secretsmanager = boto3.client("secretsmanager")


def get_private_ip(instance_id):
    response = ec2.describe_instances(InstanceIds=[instance_id])
    return response["Reservations"][0]["Instances"][0]["PrivateIpAddress"]


def get_secret(secret_arn):
    response = secretsmanager.get_secret_value(SecretId=secret_arn)
    return response["SecretString"]


def run_ssh_command(host, username, private_key_text, command):
    key_path = "/tmp/bastion_key.pem"

    with open(key_path, "w") as f:
        f.write(private_key_text)

    os.chmod(key_path, 0o600)

    key = paramiko.RSAKey.from_private_key_file(key_path)

    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())

    ssh.connect(
        hostname=host,
        username=username,
        pkey=key,
        timeout=30,
    )

    stdin, stdout, stderr = ssh.exec_command(command)

    exit_code = stdout.channel.recv_exit_status()
    out = stdout.read().decode()
    err = stderr.read().decode()

    ssh.close()

    print("STDOUT:")
    print(out)
    print("STDERR:")
    print(err)

    if exit_code != 0:
        raise Exception(f"SSH command failed with exit code {exit_code}")

    return out


def complete_lifecycle(hook_name, asg_name, lifecycle_token, result):
    autoscaling.complete_lifecycle_action(
        LifecycleHookName=hook_name,
        AutoScalingGroupName=asg_name,
        LifecycleActionToken=lifecycle_token,
        LifecycleActionResult=result,
    )


def lambda_handler(event, context):
    print("EVENT:")
    print(json.dumps(event))

    detail = event["detail"]

    instance_id = detail["EC2InstanceId"]
    asg_name = detail["AutoScalingGroupName"]
    hook_name = detail["LifecycleHookName"]
    lifecycle_token = detail["LifecycleActionToken"]

    bastion_public_ip = os.environ["BASTION_PUBLIC_IP"]
    bastion_user = os.environ.get("BASTION_USER", "ubuntu")
    secret_arn = os.environ["BASTION_PRIVATE_KEY_SECRET_ARN"]
    project_path = os.environ["ANSIBLE_PROJECT_PATH"]

    aurora_endpoint = os.environ["AURORA_ENDPOINT"]
    redis_endpoint = os.environ["REDIS_ENDPOINT"]

    private_ip = get_private_ip(instance_id)
    private_key = get_secret(secret_arn)

    if "frontend" in asg_name:
        group = "frontend"
        playbook = f"{project_path}/ansible/multi-az/deploy_frontend.yaml"
        inventory_file = "/tmp/frontend.ini"
    elif "backend" in asg_name:
        group = "backend"
        playbook = f"{project_path}/ansible/multi-az/deploy_backend.yaml"
        inventory_file = "/tmp/backend.ini"
    else:
        raise Exception(f"Unknown ASG name: {asg_name}")

    command = f"""
set -eux

cd {project_path}
git pull

cat > {inventory_file} <<EOF
[{group}]
{private_ip}
EOF

ansible-playbook \
  -i {inventory_file} \
  -u ubuntu \
  {playbook} \
  --extra-vars "aurora_endpoint={aurora_endpoint} redis_endpoint={redis_endpoint}"
"""

    try:
        run_ssh_command(
            host=bastion_public_ip,
            username=bastion_user,
            private_key_text=private_key,
            command=command,
        )

        complete_lifecycle(
            hook_name=hook_name,
            asg_name=asg_name,
            lifecycle_token=lifecycle_token,
            result="CONTINUE",
        )

        return {
            "status": "CONTINUE",
            "asg_name": asg_name,
            "instance_id": instance_id,
            "private_ip": private_ip,
            "group": group,
        }

    except Exception as e:
        print(f"ERROR: {str(e)}")

        complete_lifecycle(
            hook_name=hook_name,
            asg_name=asg_name,
            lifecycle_token=lifecycle_token,
            result="ABANDON",
        )

        raise