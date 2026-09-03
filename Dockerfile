# Serve pre-built Flutter Web output with lightweight Nginx
FROM nginx:alpine

# Flutter app root is at the branch root (flutter branch)
COPY build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
