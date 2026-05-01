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
COPY --from=build /src/dist /usr/share/nginx/html
# Azure Linux nginx's main config includes /etc/nginx/nginx.conf.default (NOT
# /etc/nginx/conf.d/*.conf), so we overwrite that file with our server block.
COPY nginx.conf /etc/nginx/nginx.conf.default
EXPOSE 80
