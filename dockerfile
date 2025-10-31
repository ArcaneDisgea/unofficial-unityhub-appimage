FROM ubuntu:latest

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install file appstream ca-certificates curl gpg -y

WORKDIR /app

COPY ./build-unityhub-appimage.sh ./
COPY ./assets ./assets
RUN chmod +x ./build-unityhub-appimage.sh ./assets/AppRun

ENTRYPOINT ["./build-unityhub-appimage.sh"]