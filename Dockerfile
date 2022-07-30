FROM linuxserver/transmission:latest

WORKDIR /home/app

RUN apk update &&  \
    apk add openssh-client --no-cache

COPY app/ ./

RUN ["./entrypoint.sh"]


