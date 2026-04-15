# Usamos a imagem oficial do Python Slim
FROM python:3.10-slim

# Instalar dependências de sistema necessárias para o OpenCV (libGL)
RUN apt-get update && apt-get install -y \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgl1-mesa-glx \
    && rm -rf /var/lib/apt/lists/*

# Definir o diretório de trabalho na nuvem
WORKDIR /app

# Copiar os requerimentos e instalar
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copiar o restante do código para dentro do container
COPY . .

# Baixar o modelo do MediaPipe durante o build para que não atrase os requests
RUN python download_utils.py

# Expor a porta 8000 para o Uvicorn
EXPOSE 8000

# Comando para iniciar a API em modo de produção
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
