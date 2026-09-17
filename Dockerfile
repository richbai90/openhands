FROM python:3.12-slim
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/
RUN apt update && apt install -y xdg-user-dirs && apt clean && \
    useradd -m -u 1000 user && \
    chown -R user:user /home/user

USER user
WORKDIR /home/user
RUN xdg-user-dirs-update && mkdir -p /home/user/.openhands
ENV PATH="/home/user/.local/bin:${PATH}"

RUN uv tool install openhands --python 3.12

ENTRYPOINT ["openhands"]
