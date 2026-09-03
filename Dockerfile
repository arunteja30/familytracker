# No Flutter needed in Docker - serve pre-built static files with Nginx
FROM nginx:alpine

# Copy the locally pre-built Flutter Web output
COPY flutter_family_tracker/build/web /usr/share/nginx/html

# Copy custom Nginx config for SPA routing + gzip + caching
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
