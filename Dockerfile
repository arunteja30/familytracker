# Stage 1: Build Flutter Web application
FROM ghcr.io/cirruslabs/flutter:stable AS build-stage

USER root
WORKDIR /app

# Ensure Git safe directory
RUN git config --global --add safe.directory '*'

# Copy project files
COPY flutter_family_tracker/ .

# Clean dependencies and build production web bundle
RUN flutter config --enable-web && \
    flutter pub get && \
    flutter build web --release --no-tree-shake-icons

# Stage 2: Serve using high-performance lightweight Nginx
FROM nginx:alpine

COPY --from=build-stage /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
