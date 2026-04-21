# syntax=docker/dockerfile:1.7
FROM node:22-bookworm-slim

ARG USER_UID=1000
ARG USER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PNPM_HOME=/home/agent/.local/share/pnpm \
    PATH=/home/agent/.local/share/pnpm:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg sudo less git tmux zsh \
        build-essential python3-minimal ripgrep fd-find \
        locales openssh-client \
    && sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen && locale-gen \
    && rm -rf /var/lib/apt/lists/*

RUN type -p curl >/dev/null \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://starship.rs/install.sh \
        | sh -s -- --yes --bin-dir /usr/local/bin

RUN if getent group node >/dev/null; then groupmod -n agent node; else groupadd -g "${USER_GID}" agent; fi \
    && groupmod -g "${USER_GID}" agent \
    && if id node >/dev/null 2>&1; then usermod -l agent -d /home/agent -m -g agent node; else useradd -m -u "${USER_UID}" -g agent -s /bin/zsh agent; fi \
    && usermod -u "${USER_UID}" -s /bin/zsh agent \
    && echo 'agent ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/agent && chmod 0440 /etc/sudoers.d/agent

RUN corepack enable \
    && corepack prepare pnpm@latest --activate \
    && mkdir -p /home/agent/.local/share/pnpm /home/agent/.cache /home/agent/.config \
    && chown -R agent:agent /home/agent

COPY --chown=agent:agent config/zshrc        /home/agent/.zshrc
COPY --chown=agent:agent config/starship.toml /home/agent/.config/starship.toml
COPY --chown=agent:agent config/tmux.conf    /home/agent/.tmux.conf

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER agent
WORKDIR /home/agent
RUN pnpm add -g @anthropic-ai/claude-code @openai/codex

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["zsh", "-l"]
