FROM golang:1.18.2-alpine3.14

WORKDIR /app
RUN apk add --no-cache git \
  && git clone https://github.com/cucxabong/aws-google-login.git \
  && cd aws-google-login \
  && go build -o /usr/local/bin/aws-google-login cmd/main.go

ENTRYPOINT [ "/usr/local/bin/aws-google-login" ]