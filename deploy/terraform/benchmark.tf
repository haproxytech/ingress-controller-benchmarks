# Copyright 2020 HAProxy Technologies LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

resource "aws_instance" "k8s-benchmarks" {
  ami = "ami-0bbe28eb2173f6167"
  instance_type = "t2.micro"
  subnet_id = aws_subnet.k8s-benchmarks.id
  vpc_security_group_ids = [aws_security_group.k8s-benchmarks.id]
  key_name = aws_key_pair.generated_key.key_name
  user_data = <<-EOF
		#! /bin/bash
                apt-get update
		apt-get -y upgrade
                apt-get -y install awscli python3-pip parallel unzip
                curl -Lo - https://github.com/haproxytech/ingress-controller-benchmarks/archive/master.tar.gz |tar -C ~ubuntu/ -xz
                mv ~ubuntu/ingress-controller-benchmarks-master ~ubuntu/ingress-controller-benchmarks
                mkdir -p ~ubuntu/ingress-controller-benchmarks/tmp/single
                mkdir -p ~ubuntu/ingress-controller-benchmarks/tmp/saturate
                printf ". ingress-controller-benchmarks/deploy/scripts/configure_k8s_cluster.sh\n" >> ~ubuntu/.profile
                mkdir ~/.aws
                printf "[default]\n" > ~/.aws/config
                printf "region = us-east-2\n" >> ~/.aws/config
                printf "[default]\n" > ~/.aws/credentials
                printf "aws_access_key_id = ${aws_iam_access_key.user.id}\n" >> ~/.aws/credentials
                printf "aws_secret_access_key = ${aws_iam_access_key.user.secret}\n" >> ~/.aws/credentials
                printf -- "${file(var.privkey_file)}" >> ~/k8s-benchmarks.id_rsa
                printf -- "${file(var.pubkey_file)}" >> ~/k8s-benchmarks.id_rsa.pub
                curl -Lo /usr/local/bin/kops https://github.com/kubernetes/kops/releases/download/$(curl -s https://api.github.com/repos/kubernetes/kops/releases/latest | grep tag_name | cut -d '"' -f 4)/kops-linux-amd64
                curl -Lo /usr/local/bin/kubectl "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
                curl -fsSL  https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 |bash
                chmod +x /usr/local/bin/kops
                chmod +x /usr/local/bin/kubectl
                pip3 install matplotlib numpy
                export AWS_ACCESS_KEY_ID=${aws_iam_access_key.user.id}
                export AWS_SECRET_ACCESS_KEY=${aws_iam_access_key.user.secret}
                aws s3api create-bucket --bucket prefix-k8sbenchmarks-kops-state-store --region us-east-1
                kops create cluster --state s3://prefix-k8sbenchmarks-kops-state-store --cloud=aws --zones=us-east-2a --node-count=6 --node-size=c5.xlarge --master-size=c5.xlarge --ssh-public-key ~/k8s-benchmarks.id_rsa.pub --yes --name k8stmp.k8s.local
                kops export kubecfg --state s3://prefix-k8sbenchmarks-kops-state-store --name k8stmp.k8s.local
                mv /.kube ~ubuntu/
                cp ~/k8s* ~ubuntu/
                cp -r ~/.aws ~ubuntu/
                chmod 700 ~ubuntu/.ssh
                chmod 600 ~ubuntu/.ssh/id_rsa
                chown -R ubuntu.ubuntu ~ubuntu/
	EOF

  depends_on = [
    aws_route_table_association.k8s-benchmarks,
    aws_route_table.k8s-benchmarks,
    aws_internet_gateway.k8s-benchmarks,
    aws_iam_user.user,
    aws_iam_group.group,
    aws_iam_group_membership.group,
    aws_iam_group_policy_attachment.group-policy-attachment,
  ]

  provisioner "remote-exec" {
      when = destroy
      inline = [
        "export AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id)",
        "export AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key)",
        "kops delete cluster --state=s3://prefix-k8sbenchmarks-kops-state-store --name k8stmp.k8s.local --yes",
        "aws s3 rb s3://prefix-k8sbenchmarks-kops-state-store --force"
      ]
#
# Unfortunately due to constraints in terraform we need to
# hardcode the filename for private_key as you can no longer
# pass variables.
#
      connection {
        type        = "ssh"
        user        = "ubuntu"
        private_key = file("k8sbenchmarks") 
        host = self.public_ip
      }
  }
}

resource "aws_key_pair" "generated_key" {
  key_name   = var.key_name
  public_key = file(var.pubkey_file)
}

resource "aws_vpc" "k8s-benchmarks" {
  cidr_block           = "192.168.0.0/16"
  instance_tenancy     = "default"
  enable_dns_hostnames = true
}

resource "aws_subnet" "k8s-benchmarks" {
  vpc_id                  = aws_vpc.k8s-benchmarks.id
  cidr_block              = "192.168.0.0/24"
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "k8s-benchmarks" {
  vpc_id = aws_vpc.k8s-benchmarks.id
}

resource "aws_route_table" "k8s-benchmarks" {
  vpc_id = aws_vpc.k8s-benchmarks.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.k8s-benchmarks.id
  }
}

resource "aws_route_table_association" "k8s-benchmarks" {
  route_table_id = aws_route_table.k8s-benchmarks.id
  subnet_id      = aws_subnet.k8s-benchmarks.id
}

resource "aws_security_group" "k8s-benchmarks" {
  name        = "k8sbenchmarks_security_group"
  description = "Allow HTTP and SSH"
  vpc_id      = aws_vpc.k8s-benchmarks.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_group" "group" {
  name = "k8s-benchmarks-kops"
}

resource "aws_iam_group_policy_attachment" "group-policy-attachment" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEC2FullAccess",
    "arn:aws:iam::aws:policy/AmazonRoute53FullAccess", 
    "arn:aws:iam::aws:policy/AmazonS3FullAccess",
    "arn:aws:iam::aws:policy/IAMFullAccess",
    "arn:aws:iam::aws:policy/AmazonVPCFullAccess"
  ])

  group      = aws_iam_group.group.name
  policy_arn = each.value
}

resource "aws_iam_user" "user" {
  name = "k8s-benchmarks-kops"
}

resource "aws_iam_group_membership" "group" {
  name = "tf-testing-group-membership"

  users = [
    aws_iam_user.user.name,
  ]

  group = aws_iam_group.group.name
}

resource "aws_iam_access_key" "user" {
  user    = aws_iam_user.user.name
}

resource "time_sleep" "wait_200_seconds" {
  create_duration = "200s"
}

output "GETTINGSTARTED" {
    value = <<GETTINGSTARTED
The benchmark instance is ready to go and the kubernetes cluster is currently being configured.
It will take a few minutes to fully spin up.
Upon connecting to the instance you will need to wait for the Kubernetes cluster to completely initialize before you are dropped to the shell.
Once you're able to access the shell you can execute the "benchmarks.sh" shell script to start the benchmarks.
A unique ssh keypair has been generated within the current working directory named "k8sbenchmarks".
Use the following command to ssh to the instance:

${format("ssh -i k8sbenchmarks ubuntu@%s", aws_instance.k8s-benchmarks.public_ip)}


Happy Benchmarking!

GETTINGSTARTED

  depends_on = [time_sleep.wait_200_seconds]

}
