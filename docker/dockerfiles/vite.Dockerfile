FROM chatwoot:development

ENV PNPM_HOME="/root/.local/share/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

RUN chmod +x docker/entrypoints/vite.sh
RUN npm install -g pnpm@10.15.0

EXPOSE 3036
CMD ["bin/vite", "dev"]
