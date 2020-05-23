FROM busybox

COPY index.html /var/www/

ENTRYPOINT [ "busybox", "httpd", "-f", "-p", "8080", "-h", "/var/www/" ]
