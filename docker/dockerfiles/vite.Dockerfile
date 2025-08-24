FROM chatwoot:development

ENV PNPM_HOME="/root/.local/share/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

RUN chmod +x docker/entrypoints/vite.sh
RUN gem install bundler -v '2.5.11'

EXPOSE 3036
CMD ["bin/vite", "dev"]
