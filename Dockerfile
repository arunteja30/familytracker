# Stage 1: Build Flutter Web application
FROM ghcr.io/cirruslabs/flutter:stable AS build-stage

USER root

# Configure git safe directory for all SDK and app paths
RUN git config --global --add safe.directory /sdks/flutter && \
    git config --global --add safe.directory '*'

WORKDIR /app

# Copy and resolve dependencies first for efficient Docker layer caching
COPY flutter_family_tracker/pubspec.yaml flutter_family_tracker/pubspec.lock ./
RUN flutter pub get

# Copy the entire Flutter app source
COPY flutter_family_tracker/ .

# Build production web bundle
RUN flutter build web --release --no-tree-shake-icons

# Stage 2: Serve using lightweight Nginx Alpine
FROM nginx:alpine

COPY --from=build-stage /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
