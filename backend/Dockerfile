FROM python:3.9-slim

WORKDIR /backend

# Instalar dependencias del sistema
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Copiar requirements.txt primero (mejor para caché de Docker)
COPY requirements.txt .

# Instalar dependencias Python
RUN pip install --no-cache-dir -r requirements.txt

# Copiar la aplicación
COPY app.py .

# Exponer puerto para Uvicorn
EXPOSE 8000

# Ejecutar con Uvicorn
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "4"]