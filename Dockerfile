# Stage 1: Build Flutter Web application
FROM ghcr.io/cirruslabs/flutter:stable AS build-stage

WORKDIR /app
COPY flutter_family_tracker/ /app/flutter_family_tracker/

WORKDIR /app/flutter_family_tracker
RUN flutter pub get
RUN flutter build web --release

# Stage 2: Serve using high-performance lightweight Nginx
FROM nginx:alpine

COPY --from=build-stage /app/flutter_family_tracker/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
