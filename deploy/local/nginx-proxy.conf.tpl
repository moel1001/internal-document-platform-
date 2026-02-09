events {}

http {
  server {
    listen 80;
    server_name grafana.local;
    location / {
      proxy_set_header Host $host;
      proxy_pass http://__NODE_IP__:__HTTP_NODEPORT__;
    }
  }

  server {
    listen 80;
    server_name prometheus.local;
    location / {
      proxy_set_header Host $host;
      proxy_pass http://__NODE_IP__:__HTTP_NODEPORT__;
    }
  }

  server {
    listen 80;
    server_name document-service.local;
    location / {
      proxy_set_header Host $host;
      proxy_pass http://__NODE_IP__:__HTTP_NODEPORT__;
    }
  }

  server {
    listen 443 ssl;
    server_name argocd.local;

    ssl_certificate     /etc/nginx/certs/argocd.local.crt;
    ssl_certificate_key /etc/nginx/certs/argocd.local.key;

    location / {
      proxy_set_header Host $host;

      proxy_pass https://__NODE_IP__:__HTTPS_NODEPORT__;
      proxy_ssl_server_name on;
      proxy_ssl_verify off;
    }
  }
}
