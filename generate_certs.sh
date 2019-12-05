#!/bin/sh

openssl genrsa -out /tmp/server.key 4096
openssl req -new -key /tmp/server.key -out /tmp/server.csr \
    -subj "/C=JP/ST=Hiroshima/L=Hiroshima/O=Deverop/OU=Deverop/CN=localhost"
openssl x509  -req -in /tmp/server.csr -days 365 -signkey /tmp/server.key -out /tmp/server.crt
