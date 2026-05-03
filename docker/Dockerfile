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
        ca-certificates curl gpg sudo less git tmux zsh \
        build-essential python3-minimal ripgrep fd-find \
        locales openssh-client \
        libsecret-1-0 libsecret-tools gnome-keyring dbus-x11 \
    && sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen && locale-gen \
    && rm -rf /var/lib/apt/lists/*

RUN command -v curl >/dev/null \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://starship.rs/install.sh \
        | sh -s -- --yes --bin-dir /usr/local/bin

RUN set -eu; \
    existing_group="$(getent group "${USER_GID}" | cut -d: -f1 || true)"; \
    if [ -n "$existing_group" ]; then \
        if [ "$existing_group" != "agent" ]; then groupmod -n agent "$existing_group"; fi; \
    elif getent group node >/dev/null; then \
        groupmod -n agent -g "${USER_GID}" node; \
    else \
        groupadd -g "${USER_GID}" agent; \
    fi; \
    existing_user="$(getent passwd "${USER_UID}" | cut -d: -f1 || true)"; \
    if [ -n "$existing_user" ]; then \
        if [ "$existing_user" != "agent" ]; then \
            usermod -l agent -d /home/agent -m -g agent -s /bin/zsh "$existing_user"; \
        else \
            usermod -g agent -s /bin/zsh agent; \
        fi; \
    elif id node >/dev/null 2>&1; then \
        usermod -l agent -d /home/agent -m -u "${USER_UID}" -g agent -s /bin/zsh node; \
    else \
        useradd -m -u "${USER_UID}" -g agent -s /bin/zsh agent; \
    fi; \
    echo 'agent ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/agent; \
    chmod 0440 /etc/sudoers.d/agent

RUN corepack enable \
    && corepack prepare pnpm@latest --activate \
    && mkdir -p /home/agent/.local/share/pnpm/store \
                /home/agent/.local/share/keyrings \
                /home/agent/.cache \
                /home/agent/.config/gh \
                /home/agent/.claude \
                /home/agent/.codex \
    && chown -R agent:agent /home/agent

COPY --chown=agent:agent config/zshrc        /home/agent/.zshrc
COPY --chown=agent:agent config/starship.toml /home/agent/.config/starship.toml
COPY --chown=agent:agent config/tmux.conf    /home/agent/.tmux.conf

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER agent
WORKDIR /home/agent
RUN pnpm add -g @anthropic-ai/claude-code @openai/codex \
    && root="$(pnpm root -g)" \
    && for pkg in @anthropic-ai/claude-code @openai/codex; do \
           if [ -f "$root/$pkg/install.cjs" ]; then \
               node "$root/$pkg/install.cjs"; \
           fi; \
       done

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["zsh", "-l"]
