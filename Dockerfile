FROM linuxserver/transmission:latest

WORKDIR /mover

RUN apk update &&  \
    apk add openssh-client --no-cache

COPY app/ /mover/

RUN echo """* * * * * /mover/setup.sh""" >> /etc/crontabs/root

