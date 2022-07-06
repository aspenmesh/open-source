#docker login registry.redhat.io
#docker pull registry.redhat.io/openshift4/ose-cli@sha256:1f033730b321137c1b834b0bcb7ea15a72f21d51e1960f89fa2cf85268dd886b
#docker run --rm -it registry.redhat.io/openshift4/ose-cli@sha256:1f033730b321137c1b834b0bcb7ea15a72f21d51e1960f89fa2cf85268dd886b

#openshift 4.10 https://catalog.redhat.com/software/containers/openshift4/ose-cli/5cd9ba3f5a13467289f4d51d
FROM registry.redhat.io/openshift4/ose-cli@sha256:1f033730b321137c1b834b0bcb7ea15a72f21d51e1960f89fa2cf85268dd886b

ARG AWS_ACCESS_KEY_ID
ARG AWS_SECRET_ACCESS_KEY
ARG AWS_DEFAULT_REGION=us-west-2
ARG YQ_VERSION=3.4.1
ARG PULL_SECRET_B64

ENV KUBECONFIG=/root/_install_/auth/kubeconfig

WORKDIR /root
RUN mkdir _install_

RUN yum update -y \
	&& yum install unzip openssh jq -y  \
    && curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"  \
    && unzip awscliv2.zip  \
    && ./aws/install \
    && wget https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64 \
    && mv yq_linux_amd64 /usr/bin/yq && chmod +x /usr/bin/yq  \
    && wget https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/4.10.18/openshift-install-linux.tar.gz -O _install_/openshift-install-linux.tar.gz \
    && tar -xf _install_/openshift-install-linux.tar.gz --directory _install_


RUN ssh-keygen -b 2048 -t rsa -f ~/_install_/id_rsa -q -N ""

COPY openshift-cluster.sh .
COPY openshift-delete-cluster.sh .
COPY template.install-config.yaml .

