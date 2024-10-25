FROM linuxserver/transmission:latest

WORKDIR /mover

RUN apk update &&  \
    apk add rsync openssh-client --no-cache

COPY app/ /mover/
RUN chmod +x /mover/*.sh

RUN echo """* * * * * /mover/setup.sh""" >> /etc/crontabs/root