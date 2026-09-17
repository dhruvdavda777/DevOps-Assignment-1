# nginx already knows how to serve static files, so the image only needs the page.
FROM nginx:1.27-alpine

# The default server block serves whatever lives in this directory.
COPY index.html /usr/share/nginx/html/index.html

EXPOSE 80
# No CMD needed: the base image already starts nginx in the foreground.
