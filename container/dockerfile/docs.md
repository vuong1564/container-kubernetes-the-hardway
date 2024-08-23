
# v1 - Original
cd app-basic
docker build -t docker-good-practices:v1 -f v1.dockerfile .

# Optimize #1 - Using '.dockerignore'
cat <<EOF > .dockerignore
# Ignore all '.terraform' directory
**/.terraform
EOF

docker build -t docker-good-practices:v1.1 -f v1.dockerfile .

# Optimize #2 - Using Dockerfile linting tool(s)
  # hadolint: https://github.com/hadolint/hadolint

docker build -t docker-good-practices:v1.2 -f v1.2.dockerfile .

# Optimize #3 - Using COPY/ADD option to change file metadata (such as: owner/permissions)
docker build  -t docker-good-practices:v1.3 -f v1.3.dockerfile .

# Optimize #4 - Write Cache Friendly Dockerfile
docker build  -t docker-good-practices:v1.4 -f v1.4.dockerfile .

# Optimize #5 - Using BuildKit cache mount
docker build -t docker-good-practices:v1.5 -f v1.5.dockerfile .

# Optimize #6 - Using multi-stages
cd multi-stage
docker build -t multi-stages:v1 -f v1.dockerfile .

docker build -t multi-stages:v2 -f v2.dockerfile .

################## 
### Secrets
################## 

# v1 - Original
docker build -t secrets:v1 -f v1.dockerfile .

# v1.1 - secrets as build argument
docker build --build-arg SSH_PRIVATE_KEY="$(cat files/dockerfile-good-practices)" -t secrets:v1.1 -f v1.1.dockerfile .

# v1.2 - using secret mount RUN option
docker build --secret id=ssh_key,src=files/dockerfile-good-practices -t secrets:v1.2 -f v1.2.dockerfile .

# v1.3 - using ssh mount RUN option
docker build --ssh default="${SSH_AUTH_SOCK}" -t secrets:v1.3 -f v1.3.dockerfile .
  OR
docker build --ssh default=files/dockerfile-good-practices -t secrets:v1.3 -f v1.3.dockerfile .
