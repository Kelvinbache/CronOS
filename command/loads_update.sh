cd .. 

cd backend

docker build -t app:latest .

minikube image load app:latest
