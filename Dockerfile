FROM alpine:latest
LABEL maintainer="gwyyaaa@gmail.com"
COPY blog /app/
COPY public /app/public/
RUN apk --update add tzdata && \
    cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone && \
    apk del tzdata && \
    rm -rf /var/cache/apk/*
ENTRYPOINT ["/app/blog"]