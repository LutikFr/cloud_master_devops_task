FROM python:3.12-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      openssh-client sshpass git curl ca-certificates \
    && pip install --no-cache-dir ansible kubernetes PyYAML jmespath \
    && ansible-galaxy collection install kubernetes.core ansible.posix \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
ENTRYPOINT ["ansible-playbook"]
