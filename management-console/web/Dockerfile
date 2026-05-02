# syntax=docker/dockerfile:1.7
# Use MCR's Mariner Node image to avoid Docker Hub anonymous pull rate limits
# during ACR remote build.
FROM mcr.microsoft.com/azurelinux/base/nodejs:24 AS build
WORKDIR /src
# Azure Linux's node:24 ships with a recent npm; bump to latest npm 11.x.
RUN npm install -g npm@11
COPY package.json package-lock.json* ./
RUN npm install --no-audit --no-fund
COPY . .
RUN npm run build

# Use MCR's nginx mirror for the same reason.
FROM mcr.microsoft.com/azurelinux/base/nginx:1.25 AS runtime
# gettext provides envsubst for rendering the nginx config from the template
# at container startup using API_BASE_URL injected by Container Apps.
RUN tdnf install -y gettext && tdnf clean all
COPY --from=build /src/dist /usr/share/nginx/html
# Ship the template (not a pre-rendered nginx.conf) so the build is fully
# self-contained — no predeploy hook needed to materialise nginx.conf into
# the build context. Azure Linux nginx's main config includes
# /etc/nginx/nginx.conf.default, which the entrypoint writes at startup.
COPY nginx.conf.template /etc/nginx/templates/nginx.conf.template
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh
EXPOSE 80
ENTRYPOINT ["/docker-entrypoint.sh"]
