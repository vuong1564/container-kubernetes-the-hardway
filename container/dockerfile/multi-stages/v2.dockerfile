FROM golang:1.18.2-alpine3.14 as builder

WORKDIR /app
RUN apk add --no-cache git \
  && git clone https://github.com/cucxabong/aws-google-login.git \
  && cd aws-google-login \
  && CGO_ENABLED=0 go build -o /usr/local/bin/aws-google-login cmd/main.go

FROM alpine:3.15.4

COPY --from=builder /usr/local/bin/aws-google-login /usr/local/bin/aws-google-login

ENTRYPOINT [ "/usr/local/bin/aws-google-login" ]
