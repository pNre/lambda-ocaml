
#!/bin/sh
docker build --tag lambda .
docker rm lambda-build || true
docker create --name lambda-build lambda
docker cp lambda-build:/app/main.exe main.exe
docker cp lambda-build:/app/hook.so hook.so
zip bootstrap.zip bootstrap hook.so main.exe
